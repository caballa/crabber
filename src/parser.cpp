#include <cctype> // isspace
#include <crab/support/os.hpp>
#include <crab_tests/crabir.hpp>
#include <crab_tests/parser.hpp>
#include <iostream>
#include <memory>
#include <regex>
#include <string>
#include <vector>

#define LPAREN R"_(\s*\(\s*)_"
#define RPAREN R"_(\s*\)\s*)_"
#define COMMA R"_(\s*,\s*)_"
#define COLON R"_(\s*:\s*)_"
#define QUOTE R"_(\")_"

#define ANY R"_(\s*(.+?)\s*)_"

#define CFG_START R"_(\s*cfg)_" LPAREN  QUOTE ANY QUOTE RPAREN

#define CMPOP R"_(\s*(<=|<|>=|>|==|=|!=)\s*)_"
#define CASTOP R"_(\s*(trunc|sext|zext)\s*)_"
#define BOOLEANOP R"_(\s*(and|or|xor)\s*)_"
#define UNARYOP R"_(\s*(not)\s*)_"

#define LABEL R"_(\s*(<\w[a-zA-Z_0-9]*>)\s*)_"
#define LABEL_DEF LABEL COLON
#define IF R"_(\s*if\s*)_"
#define ELSE R"_(\s*else\s*)_"
#define GOTO R"_(\s*goto\s*)_"

#define TRUE R"_(\s*true\s*)_"
#define FALSE R"_(\s*false\s*)_"
#define TRUE_OR_FALSE R"_(\s*(true|false)\s*)_"
#define IMM R"_(\s*([-+]?\d+)\s*)_"
#define ASSIGN R"_(\s*:=\s*)_"
#define VAR R"_(\s*([\.@a-zA-Z_][\.a-zA-Z0-9_]*)\s*)_"
#define LITERAL                                                                \
  R"_(\s*([-+]?)\s*(\d*)\s*\*?\s*([\.@a-zA-Z_][\.a-zA-Z0-9_]*)|\s*([-+]?)\s*(\d+)\s*)_"
#define TYPE R"_(\s*:\s*i(\d+)\s*)_"
#define BOOLEAN_TYPE R"_(\s*:\s*i1\s*)_"
#define LINCST ANY CMPOP ANY
#define ASSUME R"_(\s*assume)_" LPAREN LINCST RPAREN TYPE
#define ASSUME_TRIVIAL R"_(\s*assume)_" LPAREN TRUE_OR_FALSE RPAREN 
#define BOOLEAN_ASSUME R"_(\s*assume)_" LPAREN VAR RPAREN 
#define ASSERT R"_(\s*assert)_" LPAREN LINCST RPAREN TYPE
#define ASSERT_TRIVIAL R"_(\s*assert)_" LPAREN TRUE_OR_FALSE RPAREN 
#define BOOLEAN_ASSERT R"_(\s*assert)_" LPAREN VAR RPAREN
#define EXPECT_EQ R"_(\s*EXPECT_EQ)_" LPAREN TRUE_OR_FALSE COMMA ASSERT RPAREN
#define EXPECT_EQ_TRIVIAL R"_(\s*EXPECT_EQ)_" LPAREN TRUE_OR_FALSE COMMA ASSERT_TRIVIAL RPAREN
#define BOOLEAN_EXPECT_EQ R"_(\s*EXPECT_EQ)_" LPAREN TRUE_OR_FALSE COMMA BOOLEAN_ASSERT RPAREN
#define HAVOC R"_(\s*havoc)_" LPAREN VAR TYPE RPAREN
#define EXIT R"_(\s*exit)_"

namespace crab_tests {
  
using namespace std;
using namespace cfg;
using namespace crab;

static variable_t make_variable(variable_factory_t &vfac, string name,
                                variable_type type) {
  smatch m;
  if (!regex_match(name, m, regex(VAR)) ||
      name == "true" || name == "false") {
    CRAB_ERROR("cannot create a variable name \"", name, "\"");        
  }
  return variable_t(vfac[name], type);
}

static linear_constraint_t
make_linear_constraint(const string &kind, const linear_expression_t &e) {
  if (kind == "<=") {
    return linear_constraint_t(e <= 0);
  } else if (kind == "<") {
    return linear_constraint_t(e < 0);
  } else if (kind == ">=") {
    return linear_constraint_t(e >= 0);
  } else if (kind == ">") {
    return linear_constraint_t(e > 0);
  } else if (kind == "==" || kind == "=") {
    return linear_constraint_t(e == 0);
  } else if (kind == "!=") {
    return linear_constraint_t(e != 0);
  } else {
    CRAB_ERROR("parser of linear constraint cannot recognize ", kind);
  }
}

static unique_ptr<cfg_t>
make_cfg(variable_factory_t &vfac, const string &name,
         const vector<pair<string, vector<pair<string, unsigned>>>> &body,
         unsigned &assertion_counter,
         map<unsigned, expected_result> &expected_results) {

  unique_ptr<cfg_t> cfg(new cfg_t("<start>"));
  for (auto &p : body) {
    cfg->insert(p.first);
  }
  for (auto &p : body) {
    block_t &b = cfg->get_node(p.first);
    for (auto &s : p.second) {
      crab_tests::parse_instruction(s.first, s.second, b, vfac, *cfg,
                                    assertion_counter, expected_results);
    }
  }
  // TODO: parse inputs/outputs
  function_declaration_t fdecl(name, {}, {});
  cfg->set_func_decl(fdecl);
  return cfg;
}

static number_t parse_number(const string &s) { return number_t(s); }

static variable_t parse_variable(const string &s, variable_factory_t &vfac,
                                 variable_type ty) {
  return variable_t(vfac[s], ty);
}

static expected_result parse_expected_result(const std::string str) {
  if (str == "true") {
    return expected_result::OK;
  } else if (str == "false") {
    return expected_result::FAILED;
  } else {
    CRAB_ERROR("unrecognized expected result ", str);
  }
}

pair<vector<unique_ptr<cfg_t>>, unique_ptr<map<unsigned, expected_result>>>
parse_crabir(istream &is, variable_factory_t &vfac) {
  string line;
  string cur_cfg_name("");
  string cur_block("");
  vector<pair<string, unsigned>> insts;
  vector<pair<string, vector<pair<string, unsigned>>>> cur_cfg_body;
  unsigned line_number = 0;
  unsigned assertion_counter = 0;
  vector<unique_ptr<cfg_t>> cfgs;
  unique_ptr<map<unsigned, expected_result>> expected_results(
      new map<unsigned, expected_result>());

  while (getline(is, line)) {
    line_number++;
    string line_stripped = line.substr(0, line.find('#'));
    smatch m;
    if (regex_match(line_stripped, m, regex(CFG_START))) {
      // Start of a CFG
      if (cur_cfg_name != "") {
        if (cur_block != "") {
          cur_cfg_body.emplace_back(make_pair(cur_block, insts));
          insts.clear();
        }
        cfgs.emplace_back(make_cfg(vfac, cur_cfg_name, cur_cfg_body,
                                   assertion_counter, *expected_results));
        cur_cfg_body.clear();
      }
      cur_cfg_name = m[1];
    } else if (regex_match(line_stripped, m, regex(LABEL_DEF))) {
      // Start of a block
      if (cur_block != "") {
        cur_cfg_body.emplace_back(make_pair(cur_block, insts));
        insts.clear();
      }
      cur_block = m[1];
    } else {
      // Instruction (it can be a blank line)
      insts.emplace_back(make_pair(line_stripped, line_number));
    }
  }

  if (cur_block != "") {
    cur_cfg_body.emplace_back(make_pair(cur_block, insts));
    insts.clear();
  }

  if (cur_cfg_name != "") {
    cfgs.emplace_back(make_cfg(vfac, cur_cfg_name, cur_cfg_body,
                               assertion_counter, *expected_results));
    cur_cfg_body.clear();
  }
  return make_pair(std::move(cfgs), std::move(expected_results));
}

linear_expression_t parse_linear_expression(const string &exp_text,
                                            variable_factory_t &vfac,
                                            variable_type ty,
                                            unsigned line_number) {
  smatch m;
  if (regex_match(exp_text, m, regex(IMM))) {
    return linear_expression_t(parse_number(m[1]));
  }

  regex p(LITERAL);
  auto vars_begin = sregex_iterator(exp_text.begin(), exp_text.end(), p);
  auto vars_end = sregex_iterator();
  linear_expression_t e(0);
  for (sregex_iterator it = vars_begin; it != vars_end; ++it) {
    smatch match = *it;
    if (match.size() != 6) {
      CRAB_ERROR("unexpected problem while parsing linear expression ",
                 exp_text, " at line ", line_number);
    }

    // Decide which can of match: literal or immediate value
    if (match[3].str() != "") {
      // it matched a literal: "-2*x"
      string polarity_text = match[1].str();
      string coefficient_text = match[2].str();
      string var_text = match[3].str();
      number_t coefficient =
          (coefficient_text == "" ? number_t(1)
                                  : parse_number(coefficient_text));
      if (polarity_text == "+" || polarity_text == "") {
        e = e + (coefficient * parse_variable(var_text, vfac, ty));
      } else if (polarity_text == "-") {
        e = e - (coefficient * parse_variable(var_text, vfac, ty));
      } else {
        CRAB_ERROR("parser of linear expression cannot recognize polarity ",
                   polarity_text, " in ", exp_text, " at line ", line_number);
      }
    } else {
      // it matched a immediate value: "-5"
      string polarity_text = match[4].str();
      string imm_text = match[5].str();
      if (polarity_text == "+") {
        e = e + parse_number(imm_text);
      } else if (polarity_text == "-") {
        e = e - parse_number(imm_text);
      } else if (it == vars_begin) {
        e = e + parse_number(imm_text);
      } else {
        CRAB_ERROR("parser of linear expression cannot recognize polarity ",
                   polarity_text, " in ", exp_text, " at line ", line_number);
      }
    }
  }
  return e;
}

linear_constraint_t parse_linear_constraint(const string &cst_text,
                                            variable_factory_t &vfac,
                                            variable_type ty,
                                            unsigned line_number) {
  smatch m;
  if (regex_match(cst_text, m, regex(TRUE))) {
    return linear_constraint_t::get_true();
  } else if (regex_match(cst_text, m, regex(FALSE))) {
    return linear_constraint_t::get_false();
  } else if (regex_match(cst_text, m, regex(ANY CMPOP ANY))) {
    linear_expression_t e1 =
        parse_linear_expression(m[1], vfac, ty, line_number);
    string op = m[2];
    linear_expression_t e2 =
        parse_linear_expression(m[3], vfac, ty, line_number);
    return make_linear_constraint(op, e1 - e2);
  } else {
    CRAB_ERROR("cannot parse ", cst_text, " as a linear constraint at line ",
               line_number);
  }
}

static void parse_assertion_or_assume(const string &op1, const string &op2,
				      const string &cmp_op, const string &type,
				      bool is_assertion, unsigned line_number,
				      block_t &b, variable_factory_t &vfac,
				      unsigned &assertion_counter) {

  variable_type ty(INT_TYPE, std::stoi(type));
  linear_expression_t e1 = parse_linear_expression(op1, vfac, ty, line_number);
  linear_expression_t e2 = parse_linear_expression(op2, vfac, ty, line_number);
  linear_constraint_t cst = make_linear_constraint(cmp_op, e1 - e2);
  if (is_assertion) {
    crab::cfg::debug_info dbg("no-filename", line_number, 0,
                              assertion_counter++);
    b.assertion(cst, dbg);
  } else {
    b.assume(cst);
  }
}

// assert(true)
// assert(false)
// assume(true)
// assume(false)
static void parse_assertion_or_assume(const string &lit, 
				      bool is_assertion, unsigned line_number,
				      block_t &b, variable_factory_t &vfac,
				      unsigned &assertion_counter) {
  bool is_true = true;
  if (lit == "true") {
  } else if (lit == "false") {
    is_true = false;
  } else {
    CRAB_ERROR("parse_assertion_or_assume cannot recognize ", lit);
  }

  linear_constraint_t cst = (is_true ?
			     linear_constraint_t::get_true():
			     linear_constraint_t::get_false());
  if (is_assertion) {
    crab::cfg::debug_info dbg("no-filename", line_number, 0,
                              assertion_counter++);
    b.assertion(cst, dbg);
  } else {
    b.assume(cst);
  }
}

static void parse_int_cast(const string &op,
			   const string &src_str, const string &src_type_str,
			   const string &dst_str, const string &dst_type_str,
			   block_t &b, variable_factory_t &vfac) {

  auto src_bitwidth = std::stoi(src_type_str);
  auto dst_bitwidth = std::stoi(dst_type_str);
  variable_type src_type((src_bitwidth == 1) ? BOOL_TYPE: INT_TYPE, src_bitwidth);
  variable_t src = make_variable(vfac, src_str, src_type);
  variable_type dst_type((dst_bitwidth == 1) ? BOOL_TYPE: INT_TYPE, dst_bitwidth);
  variable_t dst = make_variable(vfac, dst_str, dst_type);

  if (op == "trunc") {
    b.truncate(src, dst);
  } else if (op == "sext") {
    b.sext(src, dst);
  } else if (op == "zext") {
    b.zext(src, dst);
  } else {
    CRAB_ERROR("unrecognized integer cast operation ", op);
  }
}

static void parse_boolean_binary_op(const string &op,
				    const string &lhs_str,
				    const string &op1_str,
				    const string &op2_str,
				    block_t &b, variable_factory_t &vfac) {

  variable_t lhs = make_variable(vfac, lhs_str, variable_type(BOOL_TYPE));
  variable_t op1 = make_variable(vfac, op1_str, variable_type(BOOL_TYPE));
  variable_t op2 = make_variable(vfac, op2_str, variable_type(BOOL_TYPE));

  if (op == "and") {
    b.bool_and(lhs, op1, op2);
  } else if (op == "or") {
    b.bool_or(lhs, op1, op2);    
  } else if (op == "xor") {
    b.bool_xor(lhs, op1, op2);        
  } else {
    CRAB_ERROR("unrecognized Boolean binary operator ", op);
  }
}

static void parse_unary_op(const string &op,
			   const string &lhs_str,
			   const string &rhs_str,
			   block_t &b, variable_factory_t &vfac) {
  if (op == "not") {
    variable_t lhs = make_variable(vfac, lhs_str, variable_type(BOOL_TYPE));
    variable_t rhs = make_variable(vfac, rhs_str, variable_type(BOOL_TYPE));
    b.bool_not_assign(lhs, rhs);
  } else {
    CRAB_ERROR("unrecognized unary operator ", op);
  }
}
  
void parse_instruction(const string &instruction, unsigned line_number,
                       block_t &b, variable_factory_t &vfac, cfg_t &cfg,
                       unsigned &assertion_counter,
                       map<unsigned, expected_result> &expected_results) {
  smatch m;
  string instruction_stripped = instruction.substr(0, instruction.find('#'));
  if (std::all_of(instruction_stripped.begin(), instruction_stripped.end(),
                  ::isspace)) {
    // do nothing
  } else if (regex_match(instruction_stripped, m, regex(HAVOC))) {
    variable_type ty(INT_TYPE, std::stoi(m[2]));
    variable_t var = make_variable(vfac, m[1], ty);
    b.havoc(var);
  } else if (regex_match(instruction_stripped, m, regex(VAR BOOLEAN_TYPE ASSIGN VAR))) {
    // boolean assignment
    variable_t lhs = make_variable(vfac, m[1], variable_type(BOOL_TYPE));
    variable_t rhs = make_variable(vfac, m[2], variable_type(BOOL_TYPE));    
    b.bool_assign(lhs, rhs);
  } else if (regex_match(instruction_stripped, m, regex(VAR ASSIGN ANY TYPE))) {
    // boolean assignment
    variable_t lhs = make_variable(vfac, m[1], variable_type(BOOL_TYPE));
    variable_type ty(INT_TYPE, std::stoi(m[3]));
    linear_constraint_t cst =
      parse_linear_constraint(m[2], vfac, ty, line_number);
    b.bool_assign(lhs, cst);
  } else if (regex_match(instruction_stripped, m, regex(VAR TYPE ASSIGN IMM))) {
    // integer assignment
    auto bitwidth = std::stoi(m[2]);
    if (bitwidth == 1) {
      CRAB_ERROR("cannot assign an immediate value to a Boolean variable in ",
		 instruction_stripped);
    }
    variable_type ty(INT_TYPE, bitwidth);
    variable_t lhs = make_variable(vfac, m[1], ty);
    number_t rhs(m[3]);
    b.assign(lhs, rhs);
  } else if (regex_match(instruction_stripped, m, regex(VAR TYPE ASSIGN ANY))) {
    auto bitwidth = std::stoi(m[2]);
    if (bitwidth == 1) {
      CRAB_ERROR("cannot parse ", instruction_stripped, ". Two possible reasons:\n",
		 "- cannot assign a linear expression to a Boolean variable or\n",
		 "- typing unnecessarily the left-hand side with i1");
    }    
    // integer assignment
    variable_type ty(INT_TYPE, bitwidth);
    variable_t lhs = make_variable(vfac, m[1], ty);      
    linear_expression_t e =
      parse_linear_expression(m[3], vfac, ty, line_number);
    b.assign(lhs, e);
  } else if (regex_match(instruction_stripped, m, regex(ASSUME))) {
    // integer assume
    parse_assertion_or_assume(m[1], m[3], m[2], m[4], false /*is_assertion*/,
                              line_number, b, vfac, assertion_counter);
  } else if (regex_match(instruction_stripped, m, regex(ASSUME_TRIVIAL))) {
    // integer assume
    parse_assertion_or_assume(m[1], false /*is_assertion*/,
                              line_number, b, vfac, assertion_counter);
  } else if (regex_match(instruction_stripped, m, regex(BOOLEAN_ASSUME))) {
    // boolean assume
    variable_t v = make_variable(vfac, m[1], variable_type(BOOL_TYPE));
    b.bool_assume(v);
  } else if (regex_match(instruction_stripped, m, regex(ASSERT))) {
    // integer assert
    parse_assertion_or_assume(m[1], m[3], m[2], m[4], true /*is_assertion*/,
                              line_number, b, vfac, assertion_counter);
  } else if (regex_match(instruction_stripped, m, regex(ASSERT_TRIVIAL))) {
    // integer assert
    parse_assertion_or_assume(m[1], true /*is_assertion*/,
                              line_number, b, vfac, assertion_counter);
  } else if (regex_match(instruction_stripped, m, regex(BOOLEAN_ASSERT))) {
    // boolean assert
    variable_t v = make_variable(vfac, m[1], variable_type(BOOL_TYPE));
    crab::cfg::debug_info dbg("no-filename", line_number, 0,
                              assertion_counter++);
    b.bool_assert(v, dbg);
  } else if (regex_match(instruction_stripped, m, regex(EXPECT_EQ))) {
    // integer expect_eq
    parse_assertion_or_assume(m[2], m[4], m[3], m[5], true /*is_assertion*/,
                              line_number, b, vfac, assertion_counter);
    unsigned assertion_id = assertion_counter - 1;
    expected_results[assertion_id] = parse_expected_result(m[1]);
  } else if (regex_match(instruction_stripped, m, regex(EXPECT_EQ_TRIVIAL))) {
    // integer expect_eq
    parse_assertion_or_assume(m[2], true /*is_assertion*/,
                              line_number, b, vfac, assertion_counter);
    unsigned assertion_id = assertion_counter - 1;
    expected_results[assertion_id] = parse_expected_result(m[1]);
  } else if (regex_match(instruction_stripped, m, regex(BOOLEAN_EXPECT_EQ))) {
    // boolean expect_eq    
    variable_t v = make_variable(vfac, m[2], variable_type(BOOL_TYPE));
    unsigned assertion_id = assertion_counter;
    crab::cfg::debug_info dbg("no-filename", line_number, 0,
                              assertion_id);
    assertion_counter++;    
    b.bool_assert(v, dbg);
    expected_results[assertion_id] = parse_expected_result(m[1]);
  } else if (regex_match(
                 instruction_stripped, m,
                 regex(IF LPAREN ANY RPAREN TYPE GOTO LABEL ELSE GOTO LABEL))) {
    variable_type ty(INT_TYPE, std::stoi(m[2]));
    linear_constraint_t cst =
        parse_linear_constraint(m[1], vfac, ty, line_number);
    block_t &then_bb = cfg.get_node(m[3]);
    block_t &else_bb = cfg.get_node(m[4]);
    b >> then_bb;
    b >> else_bb;
    then_bb.set_insert_point_front();
    then_bb.assume(cst);
    else_bb.set_insert_point_front();
    else_bb.assume(cst.negate());
  } else if (regex_match(instruction_stripped, m, regex(GOTO LABEL))) {
    string label = m[1];
    block_t &next_bb = cfg.get_node(m[1]);
    b >> next_bb;
  } else if (regex_match(instruction_stripped, m,
			 regex(CASTOP LPAREN VAR TYPE COMMA VAR TYPE RPAREN))) {
    // integer cast
    parse_int_cast(m[1],
		   m[2], m[3], m[4], m[5],
		   b, vfac);
  } else if (regex_match(instruction_stripped, m,
			 regex(VAR ASSIGN VAR BOOLEANOP VAR))) {
    // boolean binary operations (and/or/xor)
    parse_boolean_binary_op(m[3], m[1], m[2], m[4], b, vfac);
  } else if (regex_match(instruction_stripped, m,
			 regex(VAR ASSIGN UNARYOP LPAREN VAR RPAREN))) {
    parse_unary_op(m[2], m[1], m[3], b, vfac);
  } else if (regex_match(instruction_stripped, m, regex(EXIT))) {
    // do nothing
  } else {
    CRAB_ERROR("cannot parse ", instruction, " at line ", line_number);
  }
}

} // end namespace crab_tests
