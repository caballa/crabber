#include <cctype> // isspace
#include <crab/support/os.hpp>
#include <crab_tests/crabir.hpp>
#include <crab_tests/parser.hpp>
#include <iostream>
#include <memory>
#include <regex>
#include <string>
#include <vector>

#define TRUE R"_(\s*true\s*)_"
#define FALSE R"_(\s*false\s*)_"
#define TRUE_OR_FALSE R"_(\s*(true|false)\s*)_"
#define IMM R"_(\s*([-+]?\d+)\s*)_"
#define CMPOP R"_(\s*(<=|<|>=|>|==|=|!=|<=_u|<_u|>=_u|>_u)\s*)_"
#define ASSIGN R"_(\s*(:=)\s*)_"
#define VAR R"_(\s*([\.@a-zA-Z_][\.a-zA-Z0-9_]*)\s*)_"
#define LITERAL                                                                \
  R"_(\s*([-+]?)\s*(\d*)\s*\*?\s*([\.@a-zA-Z_][\.a-zA-Z0-9_]*)|\s*([-+]?)\s*(\d+)\s*)_"
#define LABEL R"_(\s*(<\w[a-zA-Z_0-9]*>)\s*)_"
#define LABEL_DEF LABEL COLON
#define IF R"_(\s*if\s*)_"
#define ELSE R"_(\s*else\s*)_"
#define GOTO R"_(\s*goto\s*)_"
#define ANY R"_(\s*(.+?)\s*)_"
#define LPAREN R"_(\s*\(\s*)_"
#define RPAREN R"_(\s*\)\s*)_"
#define COMMA R"_(\s*,\s*)_"
#define COLON R"_(\s*:\s*)_"
#define QUOTE R"_(\")_"
#define ASSUME R"_(\s*assume)_" LPAREN ANY CMPOP ANY RPAREN TYPE
#define ASSERT R"_(\s*assert)_" LPAREN ANY CMPOP ANY RPAREN TYPE
#define HAVOC R"_(\s*havoc)_" LPAREN VAR TYPE RPAREN
#define EXIT R"_(\s*exit)_"
#define TYPE R"_(\s*:\s*i(\d+)\s*)_"
#define CFG_START R"_(\s*cfg)_" LPAREN  QUOTE ANY QUOTE RPAREN
#define EXPECT_EQ R"_(\s*EXPECT_EQ)_" LPAREN TRUE_OR_FALSE COMMA ASSERT RPAREN

namespace crab_tests {

using namespace std;
using namespace cfg;
using namespace crab;

static variable_t make_variable(variable_factory_t &vfac, string name,
                                variable_type type) {
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
  } else if (kind == "<=_u") {
    linear_constraint_t c(e <= 0);
    c.set_unsigned();
    return c;
  } else if (kind == "<_u") {
    linear_constraint_t c(e < 0);
    c.set_unsigned();
    return c;
  } else if (kind == ">=_u") {
    linear_constraint_t c(e >= 0);
    c.set_unsigned();
    return c;
  } else if (kind == ">_u") {
    linear_constraint_t c(e > 0);
    c.set_unsigned();
    return c;
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

void parse_assertion_or_assume(const string &op1, const string &op2,
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
  } else if (regex_match(instruction_stripped, m, regex(VAR TYPE ASSIGN IMM))) {
    variable_type ty(INT_TYPE, std::stoi(m[2]));
    variable_t lhs = make_variable(vfac, m[1], ty);
    number_t rhs(m[4]);
    b.assign(lhs, rhs);
  } else if (regex_match(instruction_stripped, m, regex(VAR TYPE ASSIGN ANY))) {
    variable_type ty(INT_TYPE, std::stoi(m[2]));
    variable_t lhs = make_variable(vfac, m[1], ty);
    linear_expression_t e =
        parse_linear_expression(m[4], vfac, ty, line_number);
    b.assign(lhs, e);
  } else if (regex_match(instruction_stripped, m, regex(ASSUME))) {
    parse_assertion_or_assume(m[1], m[3], m[2], m[4], false /*is_assertion*/,
                              line_number, b, vfac, assertion_counter);
  } else if (regex_match(instruction_stripped, m, regex(ASSERT))) {
    parse_assertion_or_assume(m[1], m[3], m[2], m[4], true /*is_assertion*/,
                              line_number, b, vfac, assertion_counter);
  } else if (regex_match(instruction_stripped, m, regex(EXPECT_EQ))) {
    parse_assertion_or_assume(m[2], m[4], m[3], m[5], true /*is_assertion*/,
                              line_number, b, vfac, assertion_counter);
    unsigned assertion_id = assertion_counter - 1;
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
  } else if (regex_match(instruction_stripped, m, regex(EXIT))) {
    // do nothing
  } else {
    CRAB_ERROR("cannot parse ", instruction, " at line ", line_number);
  }
}

} // end namespace crab_tests
