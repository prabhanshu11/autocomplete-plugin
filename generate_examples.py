#!/usr/bin/env python3
"""
Generate Examples from Database

Appends real completion examples (with likes/dislikes) to the markdown report.
Follows Linux convention: generated file references the main file.
"""

import sqlite3
import os
from pathlib import Path
from typing import List, Dict


def get_db_path() -> str:
    """Get the database path."""
    xdg_data = os.environ.get('XDG_DATA_HOME', os.path.expanduser('~/.local/share'))
    db_path = os.path.join(xdg_data, 'nvim', 'autocomplete.db')

    if not os.path.exists(db_path):
        db_path = './autocomplete.db'

    return db_path


def get_examples(db_path: str, limit: int = 20) -> List[Dict]:
    """Get example completions with reviews."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get examples with feedback (liked/disliked)
    cursor.execute("""
        SELECT
            model,
            prompt_before,
            prompt_after,
            completion,
            accepted,
            liked,
            cost,
            response_time_ms,
            filetype,
            timestamp
        FROM completions
        WHERE liked IS NOT NULL OR accepted = 1
        ORDER BY timestamp DESC
        LIMIT ?
    """, (limit,))

    examples = []
    for row in cursor.fetchall():
        model, prompt_before, prompt_after, completion, accepted, liked, cost, response_time, filetype, timestamp = row

        # Truncate long prompts
        before = prompt_before[-200:] if len(prompt_before) > 200 else prompt_before
        after = prompt_after[:50] if len(prompt_after) > 50 else prompt_after

        examples.append({
            'model': model,
            'prompt_before': before,
            'prompt_after': after,
            'completion': completion,
            'accepted': bool(accepted),
            'liked': liked,  # 1=liked, 0=disliked, None=no review
            'cost': cost,
            'response_time': response_time,
            'filetype': filetype,
            'timestamp': timestamp,
        })

    conn.close()
    return examples


def generate_examples_markdown(examples: List[Dict]) -> str:
    """Generate markdown for examples section."""
    if not examples:
        return "\n## Real Completion Examples\n\nNo examples with feedback yet. Use the plugin and press Ctrl+L (like) or Ctrl+D (dislike) to generate examples!\n"

    md = ["\n---\n\n"]
    md.append("## Real Completion Examples\n\n")
    md.append("*Examples below are from actual usage with user feedback*\n\n")

    for i, ex in enumerate(examples, 1):
        # Feedback indicator
        if ex['liked'] == 1:
            feedback = "👍 **LIKED**"
            feedback_class = "Positive"
        elif ex['liked'] == 0:
            feedback = "👎 **DISLIKED**"
            feedback_class = "Negative"
        else:
            feedback = "✓ Accepted" if ex['accepted'] else "✗ Rejected"
            feedback_class = "Neutral"

        md.append(f"### Example {i}: {feedback}\n\n")
        md.append(f"**Model:** `{ex['model']}`  \n")
        md.append(f"**File Type:** `{ex['filetype']}`  \n")
        md.append(f"**Cost:** ${ex['cost']:.6f} | **Response Time:** {ex['response_time']:.0f}ms  \n")
        md.append(f"**Date:** {ex['timestamp']}\n\n")

        # Show the completion
        md.append("**Context:**\n")
        md.append("```\n")
        md.append(ex['prompt_before'])
        md.append("<CURSOR>")
        md.append(ex['prompt_after'])
        md.append("\n```\n\n")

        md.append("**Completion Suggested:**\n")
        md.append("```\n")
        md.append(ex['completion'])
        md.append("\n```\n\n")

        # Sentiment
        if ex['liked'] == 1:
            md.append("*User liked this completion - model performed well.*\n\n")
        elif ex['liked'] == 0:
            md.append("*User disliked this completion - model could improve.*\n\n")

        md.append("---\n\n")

    return ''.join(md)


def append_examples_to_report(report_path: str, examples_md: str):
    """Append examples to the markdown report."""
    # Read existing report
    with open(report_path, 'r') as f:
        content = f.read()

    # Remove old examples section if exists
    if '## Real Completion Examples' in content:
        content = content.split('## Real Completion Examples')[0].rstrip()
        # Remove trailing ---
        if content.endswith('---'):
            content = content[:-3].rstrip()

    # Append new examples
    new_content = content + '\n' + examples_md

    # Write back
    with open(report_path, 'w') as f:
        f.write(new_content)


def create_generated_notice():
    """Create a notice file pointing to the main report."""
    notice = """# MODEL_COMPARISON_GENERATED.md

⚠️ **This file is auto-generated. Do not edit manually.**

The actual report is at: **MODEL_COMPARISON.md**

To regenerate:
```bash
python3 analyze.py        # Updates model statistics
python3 generate_examples.py  # Adds real examples
```

## What This Script Does

`generate_examples.py` queries the SQLite database for completions with user feedback (likes/dislikes) and appends them as examples to MODEL_COMPARISON.md.

This follows the Linux convention:
- `MODEL_COMPARISON.md` - Main file (user can read/edit top section)
- `MODEL_COMPARISON_GENERATED.md` - This notice (points to main file)
- Examples section in main file is regenerated each run

## Example Output

Real completions with feedback are shown at the bottom of MODEL_COMPARISON.md:
- 👍 Liked completions (positive examples)
- 👎 Disliked completions (areas for improvement)
- Accepted/Rejected status
- Cost and response time for each

---

*Generated by generate_examples.py*
"""
    return notice


def main():
    """Main entry point."""
    db_path = get_db_path()

    if not os.path.exists(db_path):
        print(f"Error: Database not found at {db_path}")
        print("Use the autocomplete plugin first to generate completions.")
        return

    print(f"Loading examples from: {db_path}")

    try:
        # Get examples
        examples = get_examples(db_path, limit=20)

        if not examples:
            print("\nNo examples with feedback found.")
            print("Use the plugin and press Ctrl+L (like) or Ctrl+D (dislike) to create examples!")
            return

        print(f"Found {len(examples)} examples with feedback\n")

        # Generate markdown
        examples_md = generate_examples_markdown(examples)

        # Append to report
        report_path = Path(__file__).parent / 'MODEL_COMPARISON.md'
        append_examples_to_report(report_path, examples_md)

        # Create generated notice file
        notice_path = Path(__file__).parent / 'MODEL_COMPARISON_GENERATED.md'
        with open(notice_path, 'w') as f:
            f.write(create_generated_notice())

        print(f"✓ Examples appended to: {report_path}")
        print(f"✓ Notice file created: {notice_path}")
        print(f"\nExample breakdown:")

        liked = sum(1 for ex in examples if ex['liked'] == 1)
        disliked = sum(1 for ex in examples if ex['liked'] == 0)
        neutral = len(examples) - liked - disliked

        print(f"  👍 Liked: {liked}")
        print(f"  👎 Disliked: {disliked}")
        print(f"  ○ Neutral: {neutral}")

        print(f"\nView examples at bottom of MODEL_COMPARISON.md")

    except Exception as e:
        print(f"Error generating examples: {e}")
        import traceback
        traceback.print_exc()


if __name__ == '__main__':
    main()
