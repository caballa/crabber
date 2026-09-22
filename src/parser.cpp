#include <cctype> // isspace
#include <crab/support/os.hpp>
#include <crabber/crabir.hpp>
#include <crabber/parser.hpp>
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
// Like ANY but allows the empty string (used for optional argument lists).
#define ANY_OR_EMPTY R"_(\s*(.*?)\s*)_"

// A cfg header optionally followed by a comma-separated parameter list, e.g.
//   cfg("foo")
//   cfg("foo", in a:int, out b:int)
// Group 1: cfg name. Group 2: parameter list (empty if there are no params).
#define CFG_START                                                              \
  R"_(\s*cfg\s*\(\s*")_" ANY R"_("\s*(?:,)_" ANY R"_()?\)\s*)_"

#define CMPOP R"_(\s*(<=|<|>=|>|==|=|!=)\s*)_"
#define BOOLEANOP R"_(\s*(and|or|xor)\s*)_"
#define UNARYOP R"_(\s*(not)\s*)_"
#define MUL_OR_DIV R"_(\s*([\*/])\s*)_"

#define LABEL R"_(\s*(\w[a-zA-Z_0-9]*)\s*)_"
#define LABEL_DEF LABEL COLON
#define IF R"_(\s*if\s*)_"
#define ELSE R"_(\s*else\s*)_"
#define GOTO R"_(\s*goto\s*)_"

#define TRUE R"_(\s*true\s*)_"
#define FALSE R"_(\s*false\s*)_"
#define TRUE_OR_FALSE R"_(\s*(true|false)\s*)_"
#define IMM R"_(\s*([-+]?\d+|0[xX][0-9a-fA-F]+)\s*)_"
#define ASSIGN R"_(\s*:=\s*)_"
#define VAR R"_(\s*([\.@a-zA-Z_][\.a-zA-Z0-9_]*)\s*)_"
// Regex for a single literal (a term "k*var" or an immediate). It is not
// anchored, so parse_linear_expression iterates it over the whole string and
// separately checks that the gaps between matches contain no stray text (see
// the reject_gap check there).
#define LITERAL                                                                \
  R"_(\s*([-+]?)\s*(\d*)\s*\*?\s*([\.@a-zA-Z_][\.a-zA-Z0-9_]*)|\s*([-+]?)\s*(\d+)\s*)_"
#define NONLINEAR_MUL_OR_DIV VAR MUL_OR_DIV VAR
// A sort annotation. There are no widths: the only scalar sorts are the
// mathematical integer and the boolean, spelled ":int" and ":bool".
#define SORT R"_(\s*:\s*(int|bool)\s*)_"
// ":bool" spelled out, for the one rule that requires it: a boolean copy,
// where nothing on the right-hand side says what the sort is.
#define BOOL_SORT R"_(\s*:\s*bool\s*)_"
// The same, optional. Group is empty when absent, which means "int" (see
// parse_sort): the operator determines the sort almost everywhere, so an
// annotation is only written where nothing else can supply it.
#define OPT_SORT R"_(\s*(?::\s*(int|bool)\s*)?\s*)_"
// An array element size in bytes -- the extent of the access. Optional;
// absent means 1, which makes distinct indices independent.
#define OPT_EXTENT R"_(\s*(?:,\s*(\d+)\s*)?)_"

#define LINCST ANY CMPOP ANY
#define ASSUME R"_(\s*assume)_" LPAREN LINCST RPAREN
#define ASSUME_TRIVIAL R"_(\s*assume)_" LPAREN TRUE_OR_FALSE RPAREN
#define BOOLEAN_ASSUME R"_(\s*assume)_" LPAREN VAR RPAREN
#define ASSERT R"_(\s*assert)_" LPAREN LINCST RPAREN
#define ASSERT_TRIVIAL R"_(\s*assert)_" LPAREN TRUE_OR_FALSE RPAREN
#define BOOLEAN_ASSERT R"_(\s*assert)_" LPAREN VAR RPAREN
#define EXPECT_EQ R"_(\s*EXPECT_EQ)_" LPAREN TRUE_OR_FALSE COMMA ASSERT RPAREN
#define EXPECT_EQ_TRIVIAL R"_(\s*EXPECT_EQ)_" LPAREN TRUE_OR_FALSE COMMA ASSERT_TRIVIAL RPAREN
#define BOOLEAN_EXPECT_EQ R"_(\s*EXPECT_EQ)_" LPAREN TRUE_OR_FALSE COMMA BOOLEAN_ASSERT RPAREN
#define HAVOC R"_(\s*havoc)_" LPAREN VAR OPT_SORT RPAREN
#define VALUE_PARTITION_START R"_(\s*value_partition_start)_" LPAREN VAR RPAREN
#define VALUE_PARTITION_END R"_(\s*value_partition_end)_" LPAREN VAR RPAREN
// Array accesses. The element sort of the array is taken from the value
// loaded or stored, so an array of booleans is written by annotating that
// value; an unannotated value makes it an array of mathematical integers.
// Group 1: lhs. 2: lhs sort. 3: array. 4: index. 5: extent (empty = 1).
#define ARRAY_LOAD                                                             \
  VAR OPT_SORT ASSIGN R"_(\s*array_load)_" LPAREN VAR COMMA VAR OPT_EXTENT RPAREN
// Group 1: array. 2: index. 3: value. 4: value sort. 5: extent (empty = 1).
#define ARRAY_STORE                                                            \
  R"_(\s*array_store)_" LPAREN VAR COMMA VAR COMMA VAR OPT_SORT OPT_EXTENT RPAREN
// The one cast: false becomes 0 and true becomes 1. Named as Crab names it,
// so a dump reads back the way it was written.
#define BOOL_TO_INT VAR OPT_SORT ASSIGN R"_(\s*bool_to_int)_" LPAREN VAR RPAREN
#define EXIT R"_(\s*exit)_"

// A direction marker for a cfg formal parameter.
#define DIRECTION R"_(\s*(in|out)\s+)_"
// A single cfg formal parameter: direction name:sort, e.g. "in a:int".
// Function interfaces are always fully typed, so the sort is not optional.
// Group 1: direction. Group 2: name. Group 3: sort.
#define CFG_PARAM DIRECTION VAR SORT
// A single typed variable: name:sort, e.g. "a:int". Used for callsite
// argument and output lists, which are interfaces and so also fully typed.
// Group 1: name. Group 2: sort.
#define TYPED_VAR VAR SORT

// A call site with optional outputs on the left, e.g.
//   call foo(a:int)
//   b:int := call foo(a:int)
//   (b:int) := call foo(a:int)
//   (y:int, w:bool) := call g(x:int, z:bool)
// Group 1: outputs (empty if none). Group 2: callee name. Group 3: arguments.
#define CALLSITE                                                               \
  R"_(\s*(?:(.+?)\s*:=\s*)?call\s+)_" LABEL LPAREN ANY_OR_EMPTY RPAREN

namespace crabber {
  
using namespace std;
using namespace cfg;
using namespace crab;

// The parser matches each line against a fixed set of patterns. Building a
// std::regex compiles the pattern, which is expensive, so each pattern is
// compiled exactly once here instead of once per line as it is matched.
static const regex re_var(VAR);
static const regex re_typed_var(TYPED_VAR);
static const regex re_cfg_param(CFG_PARAM);
static const regex re_cfg_start(CFG_START);
static const regex re_label_def(LABEL_DEF);
static const regex re_imm(IMM);
static const regex re_literal(LITERAL);
static const regex re_true(TRUE);
static const regex re_false(FALSE);
static const regex re_lincst(ANY CMPOP ANY);
static const regex re_callsite(CALLSITE);
static const regex re_havoc(HAVOC);
static const regex re_array_load(ARRAY_LOAD);
static const regex re_array_store(ARRAY_STORE);
static const regex re_bool_to_int(BOOL_TO_INT);
static const regex re_bool_assign_true_or_false(VAR OPT_SORT ASSIGN TRUE_OR_FALSE);
static const regex re_bool_assign_var(VAR BOOL_SORT ASSIGN VAR);
// The right-hand side contains a comparison, which is what makes the
// left-hand side a boolean. Must be tried before the linear-assignment rule,
// whose ANY would swallow the whole constraint.
static const regex re_bool_assign_cst(VAR OPT_SORT ASSIGN ANY CMPOP ANY);
static const regex re_int_assign_imm(VAR OPT_SORT ASSIGN IMM);
static const regex re_int_assign_muldiv(VAR OPT_SORT ASSIGN NONLINEAR_MUL_OR_DIV);
static const regex re_int_assign_lin(VAR OPT_SORT ASSIGN ANY);
static const regex re_assume(ASSUME);
static const regex re_assume_trivial(ASSUME_TRIVIAL);
static const regex re_bool_assume(BOOLEAN_ASSUME);
static const regex re_assert(ASSERT);
static const regex re_assert_trivial(ASSERT_TRIVIAL);
static const regex re_bool_assert(BOOLEAN_ASSERT);
static const regex re_expect_eq(EXPECT_EQ);
static const regex re_expect_eq_trivial(EXPECT_EQ_TRIVIAL);
static const regex re_bool_expect_eq(BOOLEAN_EXPECT_EQ);
static const regex re_if(IF LPAREN ANY RPAREN GOTO LABEL ELSE GOTO LABEL);
static const regex re_goto(GOTO LABEL);
static const regex re_bool_binop(VAR OPT_SORT ASSIGN VAR BOOLEANOP VAR);
static const regex re_bool_unop(VAR OPT_SORT ASSIGN UNARYOP LPAREN VAR RPAREN);
static const regex re_value_partition_start(VALUE_PARTITION_START);
static const regex re_value_partition_end(VALUE_PARTITION_END);
static const regex re_exit(EXIT);

// Remove a trailing '#' comment from a line and canonicalize its whitespace:
// every run of whitespace outside a quoted string becomes a single space, and
// leading and trailing whitespace is dropped. A '#' inside a double-quoted
// string (e.g. a cfg name) does not start a comment, and whitespace inside one
// is left exactly as written, since it is part of the cfg's name.
//
// Collapsing the runs is not cosmetic. The grammar is whitespace-insensitive
// by construction -- every token pattern carries its own "\s*" -- so patterns
// like ANY CMPOP ANY expand to adjacent "\s*" runs surrounding lazy wildcards.
// Each such adjacency is an independent way to split a run of spaces, and they
// multiply: on a line that fails to match, std::regex explores them all. A run
// of a dozen spaces in an assignment was enough to exceed libc++'s
// backtracking limit, which throws std::regex_error and aborts. Canonicalizing
// first bounds every "\s*" to at most one character, so the blow-up cannot
// arise whatever the line looks like.
static string strip_comment(const string &line) {
  string out;
  out.reserve(line.size());
  bool in_quotes = false;
  bool pending_space = false;
  for (size_t i = 0, n = line.size(); i < n; ++i) {
    const char c = line[i];
    if (c == '"') {
      in_quotes = !in_quotes;
    } else if (c == '#' && !in_quotes) {
      break;
    } else if (!in_quotes &&
               std::isspace(static_cast<unsigned char>(c))) {
      // Emit at most one space, and only once something follows it, which
      // also takes care of trailing whitespace.
      pending_space = !out.empty();
      continue;
    }
    if (pending_space) {
      out.push_back(' ');
      pending_space = false;
    }
    out.push_back(c);
  }
  return out;
}

static variable_t make_variable(variable_factory_t &vfac, string name,
                                variable_type type) {
  smatch m;
  if (!regex_match(name, m, re_var) ||
      name == "true" || name == "false") {
    CRAB_ERROR("cannot create a variable name \"", name, "\"");
  }
  return variable_t(vfac[name], type);
}

// The two scalar sorts. Integers are mathematical: there is no width to
// carry, so nothing here has to invent one.
static variable_type int_type() { return variable_type(MATH_INT_TYPE); }
static variable_type bool_type() { return variable_type(BOOL_TYPE); }

// An OPT_SORT capture: "int", "bool", or empty. Empty means int, because that
// is the sort the language defaults to; rules whose operator already fixes the
// sort do not call this, they call expect_sort instead.
static variable_type parse_sort(const string &annotation) {
  return (annotation == "bool") ? bool_type() : int_type();
}

// Same, for a rule whose operator already determines the sort: the annotation
// is optional but may not contradict it.
static variable_type expect_sort(const string &annotation, bool want_bool,
                                 const string &instruction,
                                 unsigned line_number) {
  if (!annotation.empty() && (annotation == "bool") != want_bool) {
    CRAB_ERROR("cannot annotate the left-hand side of ", instruction,
               " with :", annotation, " at line ", line_number,
               ": the right-hand side makes it ",
               (want_bool ? "a boolean" : "an integer"));
  }
  return want_bool ? bool_type() : int_type();
}

// The element size of an array access, in bytes -- the extent, i.e. how many
// addresses the value spans and therefore which neighbouring cells the access
// invalidates. An absent operand means 1, under which distinct indices are
// independent and an array behaves as a plain map.
static number_t parse_extent(const string &extent, const string &instruction,
                             unsigned line_number) {
  if (extent.empty()) {
    return number_t(1);
  }
  auto n = std::stoul(extent);
  if (n != 1 && n != 2 && n != 4 && n != 8) {
    CRAB_ERROR("cannot parse ", instruction, " at line ", line_number,
               ": the element size must be 1, 2, 4 or 8 bytes, found ", n);
  }
  return number_t(static_cast<int64_t>(n));
}

// The array type holding elements of the given scalar sort.
static variable_type array_type_of(const variable_type &elem_ty) {
  return variable_type(elem_ty.is_bool() ? ARR_BOOL_TYPE : ARR_MATH_INT_TYPE);
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

// Parse a comma-separated list of typed variables ("a:i32, b:i64") into a
// vector of variables. Anything between matches (commas, surrounding
// parentheses) is ignored, so this also accepts "(a:i32, b:i64)".
static vector<variable_t> parse_typed_var_list(const string &s,
                                               variable_factory_t &vfac) {
  vector<variable_t> result;
  auto begin = sregex_iterator(s.begin(), s.end(), re_typed_var);
  auto end = sregex_iterator();
  for (sregex_iterator it = begin; it != end; ++it) {
    smatch m = *it;
    result.push_back(make_variable(vfac, m[1], parse_sort(m[2])));
  }
  return result;
}

// Parse a comma-separated cfg parameter list ("a:i32:in, b:i32:out") into
// input and output variables.
static void parse_function_params(const string &s, variable_factory_t &vfac,
                                  vector<variable_t> &inputs,
                                  vector<variable_t> &outputs) {
  auto begin = sregex_iterator(s.begin(), s.end(), re_cfg_param);
  auto end = sregex_iterator();
  for (sregex_iterator it = begin; it != end; ++it) {
    smatch m = *it;
    variable_t var = make_variable(vfac, m[2], parse_sort(m[3]));
    if (m[1] == "in") {
      inputs.push_back(var);
    } else {
      outputs.push_back(var);
    }
  }
}

// Return true if some block reachable from the entry has no successors,
// i.e. the cfg has at least one sink that could serve as an exit block.
static bool cfg_has_reachable_sink(const cfg_t &cfg) {
  std::set<cfg_t::basic_block_label_t> visited;
  vector<cfg_t::basic_block_label_t> worklist{cfg.entry()};
  while (!worklist.empty()) {
    auto label = worklist.back();
    worklist.pop_back();
    if (!visited.insert(label).second) {
      continue;
    }
    const block_t &b = cfg.get_node(label);
    if (b.out_degree() == 0) {
      return true;
    }
    for (auto const &succ : cfg.next_nodes(label)) {
      worklist.push_back(succ);
    }
  }
  return false;
}

static unique_ptr<cfg_t>
make_cfg(variable_factory_t &vfac, const string &name, const string &params,
         const vector<pair<string, vector<pair<string, unsigned>>>> &body,
         unsigned &assertion_counter,
         map<unsigned, expected_result> &expected_results) {

  unique_ptr<cfg_t> cfg = make_unique<cfg_t>("start");
  for (auto &p : body) {
    cfg->insert(p.first);
  }
  for (auto &p : body) {
    block_t &b = cfg->get_node(p.first);
    for (auto &s : p.second) {
      crabber::parse_instruction(s.first, s.second, b, vfac, *cfg,
                                    assertion_counter, expected_results);
    }
  }

  // A cfg is created with only an entry ("start") block. The
  // interprocedural analysis also requires a dedicated exit block, so
  // ask the cfg to build one. We use a label that is unlikely to be
  // used by a CrabIR program, and bail out if the program happens to
  // define a block with that same name.
  //
  // make_exit builds the exit out of the reachable blocks without
  // successors, and errors if there are none (a function that never
  // returns). Such a function legitimately has no exit block, so we
  // only ask for one when a reachable sink exists.
  const string exit_block_name("___exit");
  for (auto &p : body) {
    if (p.first == exit_block_name) {
      CRAB_ERROR("cannot create a dedicated exit block for cfg \"", name,
                 "\" because it already defines a block named \"",
                 exit_block_name, "\"");
    }
  }
  if (cfg_has_reachable_sink(*cfg)) {
    cfg->make_exit(exit_block_name);
  }

  vector<variable_t> inputs, outputs;
  parse_function_params(params, vfac, inputs, outputs);
  function_declaration_t fdecl(name, inputs, outputs);
  cfg->set_func_decl(fdecl);
  return cfg;
}

/** if the first two characters are 0x or 0X, hexadecimal is
 *   assumed, if the first two characters are 0b or 0B, binary is
 *   assumed, otherwise if the first character is 0, octal is assumed,
 *   otherwise decimal is assumed.
 **/
static number_t parse_number(const string &s) {
  return number_t(s, 0); // default base which is choosen based on above description
}

// Every variable occurring in a linear expression or constraint is an
// integer; booleans never appear in one.
static variable_t parse_variable(const string &s, variable_factory_t &vfac) {
  return variable_t(vfac[s], int_type());
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
  string cur_cfg_params("");
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
    string line_stripped = strip_comment(line);
    smatch m;
    if (regex_match(line_stripped, m, re_cfg_start)) {
      // Start of a CFG
      if (cur_cfg_name != "") {
        if (cur_block != "") {
          cur_cfg_body.emplace_back(make_pair(cur_block, insts));
          insts.clear();
        }
        cfgs.emplace_back(make_cfg(vfac, cur_cfg_name, cur_cfg_params,
                                   cur_cfg_body, assertion_counter,
                                   *expected_results));
        cur_cfg_body.clear();
      }
      cur_cfg_name = m[1];
      cur_cfg_params = m[2];
    } else if (regex_match(line_stripped, m, re_label_def)) {
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
    cfgs.emplace_back(make_cfg(vfac, cur_cfg_name, cur_cfg_params,
                               cur_cfg_body, assertion_counter,
                               *expected_results));
    cur_cfg_body.clear();
  }

  if (cfgs.empty()) {
    CRAB_ERROR("No cfg found");
  }
  return make_pair(std::move(cfgs), std::move(expected_results));
}

linear_expression_t parse_linear_expression(const string &exp_text,
                                            variable_factory_t &vfac,
                                            unsigned line_number) {
  smatch m;
  if (regex_match(exp_text, m, re_imm)) {
    return linear_expression_t(parse_number(m[1]));
  }

  auto vars_begin = sregex_iterator(exp_text.begin(), exp_text.end(), re_literal);
  auto vars_end = sregex_iterator();
  linear_expression_t e(0);
  // The LITERAL pattern is not anchored, so sregex_iterator would silently skip
  // over anything between matches. Track how much of the string the matched
  // terms cover and reject any stray text left in the gaps, otherwise
  // "2*x ; 3*y" would parse as "2*x + 3*y" with the ";" dropped. Whitespace and
  // parentheses are tolerated: parentheses have no arithmetic meaning here but
  // leak in from constraint delimiters (e.g. the "(x == 10)" in
  // "b := (x == 10):i32", whose surrounding parens are captured with the body).
  size_t consumed = 0;
  auto reject_gap = [&](size_t from, size_t to) {
    for (size_t i = from; i < to; ++i) {
      char c = exp_text[i];
      if (!std::isspace(static_cast<unsigned char>(c)) && c != '(' && c != ')') {
        CRAB_ERROR("unexpected token near '", exp_text.substr(i),
                   "' while parsing linear expression '", exp_text,
                   "' at line ", line_number);
      }
    }
  };
  for (sregex_iterator it = vars_begin; it != vars_end; ++it) {
    smatch match = *it;
    if (match.size() != 6) {
      CRAB_ERROR("unexpected problem while parsing linear expression ",
                 exp_text, " at line ", line_number);
    }
    size_t start = static_cast<size_t>(match.position(0));
    reject_gap(consumed, start);
    consumed = start + static_cast<size_t>(match.length(0));

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
        e = e + (coefficient * parse_variable(var_text, vfac));
      } else if (polarity_text == "-") {
        e = e - (coefficient * parse_variable(var_text, vfac));
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
  reject_gap(consumed, exp_text.size());
  return e;
}

linear_constraint_t parse_linear_constraint(const string &cst_text,
                                            variable_factory_t &vfac,
                                            unsigned line_number) {
  smatch m;
  if (regex_match(cst_text, m, re_true)) {
    return linear_constraint_t::get_true();
  } else if (regex_match(cst_text, m, re_false)) {
    return linear_constraint_t::get_false();
  } else if (regex_match(cst_text, m, re_lincst)) {
    linear_expression_t e1 = parse_linear_expression(m[1], vfac, line_number);
    string op = m[2];
    linear_expression_t e2 = parse_linear_expression(m[3], vfac, line_number);
    return make_linear_constraint(op, e1 - e2);
  } else {
    CRAB_ERROR("cannot parse ", cst_text, " as a linear constraint at line ",
               line_number);
  }
}

static void parse_assertion_or_assume(const string &op1, const string &op2,
				      const string &cmp_op,
				      bool is_assertion, unsigned line_number,
				      block_t &b, variable_factory_t &vfac,
				      unsigned &assertion_counter) {

  linear_expression_t e1 = parse_linear_expression(op1, vfac, line_number);
  linear_expression_t e2 = parse_linear_expression(op2, vfac, line_number);
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

static void parse_boolean_binary_op(const string &op,
				    const string &lhs_str,
				    const string &op1_str,
				    const string &op2_str,
				    block_t &b, variable_factory_t &vfac) {

  variable_t lhs = make_variable(vfac, lhs_str, bool_type());
  variable_t op1 = make_variable(vfac, op1_str, bool_type());
  variable_t op2 = make_variable(vfac, op2_str, bool_type());

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
    variable_t lhs = make_variable(vfac, lhs_str, bool_type());
    variable_t rhs = make_variable(vfac, rhs_str, bool_type());
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
  string instruction_stripped = strip_comment(instruction);
  if (std::all_of(instruction_stripped.begin(), instruction_stripped.end(),
                  ::isspace)) {
    // do nothing
  } else if (regex_match(instruction_stripped, m, re_callsite)) {
    // function call: (outputs) := call callee(inputs)
    // Must be matched before the assignment rules below, otherwise a
    // single-output call would be mistaken for an assignment whose
    // right-hand side is a linear expression.
    vector<variable_t> outputs = parse_typed_var_list(m[1], vfac);
    vector<variable_t> inputs = parse_typed_var_list(m[3], vfac);
    b.callsite(m[2], outputs, inputs);
  } else if (regex_match(instruction_stripped, m, re_havoc)) {
    b.havoc(make_variable(vfac, m[1], parse_sort(m[2])));
  } else if (regex_match(instruction_stripped, m, re_array_load)) {
    // The array's element sort comes from the destination: annotate it
    // :bool to read from an array of booleans.
    variable_type lhs_ty = parse_sort(m[2]);
    auto lhs_var = make_variable(vfac, m[1], lhs_ty);
    auto array_var = make_variable(vfac, m[3], array_type_of(lhs_ty));
    auto idx_var = make_variable(vfac, m[4], int_type());
    b.array_load(lhs_var, array_var, idx_var,
                 parse_extent(m[5], instruction_stripped, line_number));
  } else if (regex_match(instruction_stripped, m, re_array_store)) {
    // Likewise, from the value stored.
    variable_type val_ty = parse_sort(m[4]);
    auto array_var = make_variable(vfac, m[1], array_type_of(val_ty));
    auto idx_var = make_variable(vfac, m[2], int_type());
    auto val_var = make_variable(vfac, m[3], val_ty);
    b.array_store(array_var, idx_var, val_var,
                  parse_extent(m[5], instruction_stripped, line_number));
  } else if (regex_match(instruction_stripped, m, re_bool_to_int)) {
    // The only cast in the language. Must precede the assignment rules,
    // whose right-hand side would otherwise swallow "bool_to_int(b)".
    variable_t dst = make_variable(
        vfac, m[1],
        expect_sort(m[2], false /*want_bool*/, instruction_stripped,
                    line_number));
    variable_t src = make_variable(vfac, m[3], bool_type());
    b.bool_to_int(src, dst);
  } else if (regex_match(instruction_stripped, m, re_bool_assign_true_or_false)) {
    // boolean constant
    variable_t lhs = make_variable(
        vfac, m[1],
        expect_sort(m[2], true /*want_bool*/, instruction_stripped,
                    line_number));
    b.bool_assign(lhs, m[3] == "true" ? linear_constraint_t::get_true()
                                      : linear_constraint_t::get_false());
  } else if (regex_match(instruction_stripped, m, re_bool_binop)) {
    // boolean binary operations (and/or/xor)
    expect_sort(m[2], true /*want_bool*/, instruction_stripped, line_number);
    parse_boolean_binary_op(m[4], m[1], m[3], m[5], b, vfac);
  } else if (regex_match(instruction_stripped, m, re_bool_unop)) {
    expect_sort(m[2], true /*want_bool*/, instruction_stripped, line_number);
    parse_unary_op(m[3], m[1], m[4], b, vfac);
  } else if (regex_match(instruction_stripped, m, re_bool_assign_var)) {
    // boolean copy. The one assignment whose right-hand side says nothing
    // about the sort, which is why the annotation is mandatory here.
    variable_t lhs = make_variable(vfac, m[1], bool_type());
    variable_t rhs = make_variable(vfac, m[2], bool_type());
    b.bool_assign(lhs, rhs);
  } else if (regex_match(instruction_stripped, m, re_bool_assign_cst)) {
    // the right-hand side is a comparison, so the left-hand side is boolean
    variable_t lhs = make_variable(
        vfac, m[1],
        expect_sort(m[2], true /*want_bool*/, instruction_stripped,
                    line_number));
    linear_expression_t e1 = parse_linear_expression(m[3], vfac, line_number);
    linear_expression_t e2 = parse_linear_expression(m[5], vfac, line_number);
    b.bool_assign(lhs, make_linear_constraint(m[4], e1 - e2));
  } else if (regex_match(instruction_stripped, m, re_int_assign_imm)) {
    // integer assignment where rhs is an immediate value
    variable_t lhs = make_variable(
        vfac, m[1],
        expect_sort(m[2], false /*want_bool*/, instruction_stripped,
                    line_number));
    b.assign(lhs, parse_number(m[3]));
  } else if (regex_match(instruction_stripped, m, re_int_assign_muldiv)) {
    variable_type ty = expect_sort(m[2], false /*want_bool*/,
                                   instruction_stripped, line_number);
    variable_t lhs = make_variable(vfac, m[1], ty);
    variable_t op1 = make_variable(vfac, m[3], ty);
    variable_t op2 = make_variable(vfac, m[5], ty);
    string op = m[4];
    if (op == "*") {
      b.mul(lhs, op1, op2);
    } else if (op == "/") {
      b.div(lhs, op1, op2);
    } else {
      CRAB_ERROR("unrecognized operator on the rhs in ", instruction_stripped,
		 " at line ", line_number);
    }
  } else if (regex_match(instruction_stripped, m, re_int_assign_lin)) {
    // integer assignment where rhs is a linear expression
    variable_t lhs = make_variable(
        vfac, m[1],
        expect_sort(m[2], false /*want_bool*/, instruction_stripped,
                    line_number));
    b.assign(lhs, parse_linear_expression(m[3], vfac, line_number));
  } else if (regex_match(instruction_stripped, m, re_assume)) {
    // integer assume
    parse_assertion_or_assume(m[1], m[3], m[2], false /*is_assertion*/,
                              line_number, b, vfac, assertion_counter);
  } else if (regex_match(instruction_stripped, m, re_assume_trivial)) {
    parse_assertion_or_assume(m[1], false /*is_assertion*/,
                              line_number, b, vfac, assertion_counter);
  } else if (regex_match(instruction_stripped, m, re_bool_assume)) {
    // boolean assume
    b.bool_assume(make_variable(vfac, m[1], bool_type()));
  } else if (regex_match(instruction_stripped, m, re_assert)) {
    // integer assert
    parse_assertion_or_assume(m[1], m[3], m[2], true /*is_assertion*/,
                              line_number, b, vfac, assertion_counter);
  } else if (regex_match(instruction_stripped, m, re_assert_trivial)) {
    parse_assertion_or_assume(m[1], true /*is_assertion*/,
                              line_number, b, vfac, assertion_counter);
  } else if (regex_match(instruction_stripped, m, re_bool_assert)) {
    // boolean assert
    variable_t v = make_variable(vfac, m[1], bool_type());
    crab::cfg::debug_info dbg("no-filename", line_number, 0,
                              assertion_counter++);
    b.bool_assert(v, dbg);
  } else if (regex_match(instruction_stripped, m, re_expect_eq)) {
    parse_assertion_or_assume(m[2], m[4], m[3], true /*is_assertion*/,
                              line_number, b, vfac, assertion_counter);
    expected_results[assertion_counter - 1] = parse_expected_result(m[1]);
  } else if (regex_match(instruction_stripped, m, re_expect_eq_trivial)) {
    parse_assertion_or_assume(m[2], true /*is_assertion*/,
                              line_number, b, vfac, assertion_counter);
    expected_results[assertion_counter - 1] = parse_expected_result(m[1]);
  } else if (regex_match(instruction_stripped, m, re_bool_expect_eq)) {
    // boolean expect_eq
    variable_t v = make_variable(vfac, m[2], bool_type());
    unsigned assertion_id = assertion_counter;
    crab::cfg::debug_info dbg("no-filename", line_number, 0, assertion_id);
    assertion_counter++;
    b.bool_assert(v, dbg);
    expected_results[assertion_id] = parse_expected_result(m[1]);
  } else if (regex_match(instruction_stripped, m, re_if)) {
    string cond_text = m[1];
    string then_label = m[2];
    string else_label = m[3];
    block_t &edge_then_bb = cfg.insert("edge-" + b.label() + "-" + then_label);
    block_t &edge_else_bb = cfg.insert("edge-" + b.label() + "-" + else_label);
    block_t &then_bb = cfg.get_node(then_label);
    block_t &else_bb = cfg.get_node(else_label);
    b >> edge_then_bb;
    b >> edge_else_bb;
    edge_then_bb >> then_bb;
    edge_else_bb >> else_bb;
    // A bare variable as the condition is a boolean, the same reading
    // assume(b) and assert(b) already have. "true" and "false" are excluded
    // so they keep falling through to the constraint path below, which maps
    // them to a tautology and a contradiction; treated as variables they
    // would be rejected as illegal names instead.
    smatch cond;
    if (regex_match(cond_text, cond, re_var) && cond[1] != "true" &&
        cond[1] != "false") {
      variable_t c = make_variable(vfac, cond[1], bool_type());
      edge_then_bb.bool_assume(c);
      edge_else_bb.bool_not_assume(c);
    } else {
      linear_constraint_t cst =
          parse_linear_constraint(cond_text, vfac, line_number);
      edge_then_bb.assume(cst);
      edge_else_bb.assume(cst.negate());
    }
  } else if (regex_match(instruction_stripped, m, re_goto)) {
    block_t &next_bb = cfg.get_node(m[1]);
    b >> next_bb;
  } else if (regex_match(instruction_stripped, m, re_value_partition_start)) {
    auto var = variable_or_constant_t(make_variable(vfac, m[1], int_type()));
    b.intrinsic("value_partition_start",{},{var});
  } else if (regex_match(instruction_stripped, m, re_value_partition_end)) {
    auto var = variable_or_constant_t(make_variable(vfac, m[1], int_type()));
    b.intrinsic("value_partition_end",{},{var});
  } else if (regex_match(instruction_stripped, m, re_exit)) {
    // do nothing
  } else {
    CRAB_ERROR("cannot parse ", instruction, " at line ", line_number);
  }
}

} // end namespace crabber
