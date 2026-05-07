#!/usr/bin/env bash
# Blog post validator - checks Hugo frontmatter before commit/push
# Ensures all posts have required fields with consistent formatting

set -e

BLOG_DIR="/root/aispace/tcloudblog/content/posts"
ERRORS=0

echo "🔍 Validating blog posts in $BLOG_DIR..."

for file in "$BLOG_DIR"/*.md; do
    filename=$(basename "$file")
    errors_in_file=0

    # Check title exists and is not empty
    title=$(grep -m1 '^title:' "$file" | sed 's/^title: *"\{0,1\}//; s/"\{0,1\}$//' | tr -d '"')
    if [ -z "$title" ]; then
        echo "  ❌ $filename: missing or empty 'title' in frontmatter"
        errors_in_file=$((errors_in_file + 1))
    fi

    # Check date exists and is in YYYY-MM-DD format (no timestamp)
    date_val=$(grep -m1 '^date:' "$file" | sed 's/^date: *//; s/["T+].*//')
    if ! echo "$date_val" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        echo "  ❌ $filename: invalid date format '$date_val' (expected YYYY-MM-DD)"
        errors_in_file=$((errors_in_file + 1))
    fi

    # Check tags exist
    if ! grep -q '^tags:' "$file"; then
        echo "  ❌ $filename: missing 'tags' in frontmatter"
        errors_in_file=$((errors_in_file + 1))
    fi

    # Check summary exists
    summary=$(grep -m1 '^summary:' "$file" | sed 's/^summary: *"\{0,1\}//; s/"\{0,1\}$//')
    if [ -z "$summary" ]; then
        echo "  ⚠️  $filename: missing or empty 'summary' in frontmatter"
    fi

    # Check tags format consistency (should use quoted strings)
    if grep -q '^tags: \[[a-z]' "$file"; then
        echo "  ⚠️  $filename: tags should use quoted strings like [\"AI\", \"LLM\"]"
    fi

    ERRORS=$((ERRORS + errors_in_file))
done

if [ $ERRORS -gt 0 ]; then
    echo ""
    echo "❌ Found $ERRORS error(s). Fix them before pushing."
    exit 1
else
    echo "✅ All posts passed validation!"
    exit 0
fi
