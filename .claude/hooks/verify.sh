#!/bin/bash
# .claude/hooks/pytest-verify.sh

LOGFILE=".claude/logs/pytest-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .claude/logs

# 1. 테스트 디렉토리 존재 확인
if [ ! -d "tests/unit" ]; then
    exit 0
fi

# 2. Python 파일 변경 여부 확인 (GitButler 호환)
PYTHON_CHANGED=$(git status --porcelain 2>/dev/null | grep -E "\.py$" || true)

if [ -z "$PYTHON_CHANGED" ]; then
    echo "⏭️  No Python files changed, skipping pytest"
    exit 0
fi

echo ""
echo "========================================"
echo "🧪 PYTEST VERIFICATION"
echo "========================================"
echo ""

# 전체 로그 저장 + 화면 출력
pytest tests/unit/ \
    --tb=short \
    --no-header \
    -v \
    --failed-first \
    -x \
    2>&1 | tee "$LOGFILE"

EXIT_CODE=${PIPESTATUS[0]}

# 통계
TOTAL=$(grep -cE "^tests/.*::" "$LOGFILE" 2>/dev/null || echo "0")
PASSED=$(grep -c " PASSED" "$LOGFILE" 2>/dev/null || echo "0")
FAILED=$(grep -c " FAILED" "$LOGFILE" 2>/dev/null || echo "0")

echo ""
echo "----------------------------------------"
echo "SUMMARY"
echo "----------------------------------------"

if [ $EXIT_CODE -eq 0 ]; then
    echo "Result: ✅ PASSED ($PASSED/$TOTAL tests)"
else
    echo "Result: ❌ FAILED ($FAILED failed, $PASSED passed)"
    echo ""
    echo "Failed test:"
    grep -E "^FAILED|^tests/.*FAILED" "$LOGFILE" | head -1
    echo ""
    echo "Log: $LOGFILE"
    echo "Action: Fix the failing test above, then continue"
fi

echo "----------------------------------------"
echo ""

exit 0