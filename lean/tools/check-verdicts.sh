#!/bin/sh
#
# Test oracle for --verify-with-lean.
#
#   check-verdicts.sh <crabber> '<expected>' <crabber args...>
#
# where <expected> is a ','-separated list of '<verdict> <cfg>' pairs, as in
#
#   check-verdicts.sh ./crabber 'proved bar,could not verify foo' test-1.crabir -d int
#
# Exits 0 when the set of verdicts crabber reported is exactly <expected>.
#
# ## Why this is not the exit code
#
# Every other test here uses crabber's own exit status as the oracle, because
# crabber exits non-zero when an EXPECT_EQ does not match. That status says
# nothing about the Lean run: it reflects Crab's assertion checking, and it is
# the same whether Lean proved the invariants, failed to, or was never asked.
# Before this script, `test-4 -d oct-snf` was a registered, passing test for the
# entire time its Lean verification was silently broken.
#
# ## Why the whole set, rather than grepping for one line
#
# A missing verdict is as much a regression as a wrong one -- a cfg that stops
# being checked at all would pass any per-line grep. Comparing the full set
# catches that, and catches a *new* cfg appearing.
#
# ## Why the negative expectations are pinned too
#
# 'could not verify foo' is the expected result for test-1: the assertion there
# genuinely fails, and Lean is right to refuse it. Pinning it means a change that
# accidentally "proves" a false obligation fails the suite, which is the one kind
# of regression that matters more than a proof that stopped going through.
#
# ## What is deliberately not compared
#
# Only the verdict and the cfg name. The detail after the ':' is prose -- an
# omega message, the name of an unmodelled construct -- and pinning it would make
# every reworded diagnostic a test failure. The verdict is the claim; the detail
# is the explanation.

set -u

if [ $# -lt 3 ]; then
  echo "usage: $0 <crabber> '<expected>' <crabber args...>" >&2
  exit 2
fi

crabber=$1
expected=$2
shift 2

# Sorted, so the test does not depend on the order the call graph happens to
# hand back its entries.
#
# The separator is ',' and not the more natural ';' because the caller is
# CMakeLists.txt, where a ';' inside a string is a list separator: an expected
# value written with one arrives here already split across several arguments.
normalise() {
  tr ',' '\n' | sed '/^[[:space:]]*$/d' | sort | tr '\n' ';'
}

# The five verdicts describe() can print, each matched by name. Taking a fixed
# number of leading columns would be shorter and would break the day one of them
# is renamed to something longer than its padding.
actual=$("$crabber" "$@" --verify-with-lean 2>&1 | sed -n \
  -e 's/^proved  *\([^ ]*\) :.*/proved \1/p' \
  -e 's/^could not verify  *\([^ ]*\) :.*/could not verify \1/p' \
  -e 's/^not attempted  *\([^ ]*\) :.*/not attempted \1/p' \
  -e 's/^gave up  *\([^ ]*\) :.*/gave up \1/p' \
  -e 's/^not checked  *\([^ ]*\) :.*/not checked \1/p' \
  | normalise)

want=$(printf '%s' "$expected" | normalise)

if [ "$actual" = "$want" ]; then
  exit 0
fi

echo "lean verdicts do not match for: $*"
echo "  expected: $want"
echo "  actual:   $actual"
exit 1
