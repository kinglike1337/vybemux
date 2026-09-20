# Markdown Lint Configuration for vybemux
# https://github.com/markdownlint/markdownlint

all

# Line length: 200 chars (tables and comparisons can be inherently wide);
# Tables excluded (otherwise >200-character rows in comparison tables).
rule 'MD013', :line_length => 200, :tables => false

# Excluded rules (too strict or not applicable for our use case)
exclude_rule 'MD001'   # Header levels should only increment by one
exclude_rule 'MD005'   # Inconsistent list indentation
exclude_rule 'MD007'   # Unordered list indentation
exclude_rule 'MD022'   # Headers should be surrounded by blank lines
exclude_rule 'MD024'   # Multiple headers with same content
exclude_rule 'MD025'   # Multiple top level headers (common in READMEs)
exclude_rule 'MD029'   # Ordered list item prefix style
exclude_rule 'MD031'   # Fenced code blocks should be surrounded by blank lines
exclude_rule 'MD032'   # Lists should be surrounded by blank lines
exclude_rule 'MD033'   # Inline HTML (sometimes needed)
exclude_rule 'MD034'   # Bare URL used
exclude_rule 'MD040'   # Fenced code blocks should have language specified
exclude_rule 'MD041'   # First line in file should be a top level header
exclude_rule 'MD055'   # Table row doesn't begin/end with pipes (Key Info Links)
exclude_rule 'MD057'   # Table has missing/invalid header separation (Key Info Links)
exclude_rule 'MD036'   # Emphasis used instead of a header (allow bold warnings)
exclude_rule 'MD026'   # Trailing punctuation in header (false positives from bash comments in code blocks)
