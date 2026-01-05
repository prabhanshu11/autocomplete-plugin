#!/usr/bin/env python3
"""
Autocomplete Plugin Analytics

Analyzes SQLite database of completion requests and generates reports.
"""

import sqlite3
import os
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Tuple
import json


def get_db_path() -> str:
    """Get the database path from Neovim's data directory."""
    # Try to find nvim data directory
    xdg_data = os.environ.get('XDG_DATA_HOME', os.path.expanduser('~/.local/share'))
    db_path = os.path.join(xdg_data, 'nvim', 'autocomplete.db')

    if not os.path.exists(db_path):
        # Fallback to current directory
        db_path = './autocomplete.db'

    return db_path


def calculate_quality_score(accepted: int, liked: int, disliked: int, total: int) -> float:
    """
    Calculate quality score (0-1) based on user feedback.

    Formula:
    - Acceptance rate: 40% weight
    - Like rate (of accepted): 40% weight
    - Dislike penalty: 20% weight

    Returns float between 0 and 1
    """
    if total == 0:
        return 0.0

    acceptance_rate = accepted / total

    # Like/dislike rate only considers reviewed completions
    reviewed = liked + disliked
    if reviewed > 0:
        like_rate = liked / reviewed
        dislike_penalty = disliked / reviewed
    else:
        like_rate = 0.5  # Neutral if no reviews
        dislike_penalty = 0.0

    # Weighted score
    score = (
        0.4 * acceptance_rate +
        0.4 * like_rate +
        0.2 * (1 - dislike_penalty)
    )

    return round(score, 3)


def analyze_database(db_path: str) -> Dict:
    """Analyze the database and return statistics."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get per-model statistics
    cursor.execute("""
        SELECT
            model,
            COUNT(*) as total_completions,
            SUM(accepted) as accepted_count,
            SUM(CASE WHEN liked = 1 THEN 1 ELSE 0 END) as liked_count,
            SUM(CASE WHEN liked = 0 THEN 1 ELSE 0 END) as disliked_count,
            AVG(cost) as avg_cost,
            SUM(cost) as total_cost,
            AVG(response_time_ms) as avg_response_time,
            AVG(prompt_tokens) as avg_prompt_tokens,
            AVG(completion_tokens) as avg_completion_tokens
        FROM completions
        GROUP BY model
        ORDER BY total_completions DESC
    """)

    models = []
    for row in cursor.fetchall():
        model, total, accepted, liked, disliked, avg_cost, total_cost, avg_time, avg_prompt, avg_completion = row

        quality_score = calculate_quality_score(
            accepted or 0,
            liked or 0,
            disliked or 0,
            total
        )

        models.append({
            'model': model,
            'total_completions': total,
            'accepted_count': accepted or 0,
            'liked_count': liked or 0,
            'disliked_count': disliked or 0,
            'quality_score': quality_score,
            'avg_cost': avg_cost or 0,
            'total_cost': total_cost or 0,
            'avg_response_time': avg_time or 0,
            'avg_prompt_tokens': avg_prompt or 0,
            'avg_completion_tokens': avg_completion or 0,
        })

    # Get overall statistics
    cursor.execute("""
        SELECT
            COUNT(*) as total_completions,
            SUM(accepted) as total_accepted,
            SUM(CASE WHEN liked = 1 THEN 1 ELSE 0 END) as total_liked,
            SUM(CASE WHEN liked = 0 THEN 1 ELSE 0 END) as total_disliked,
            SUM(cost) as total_cost,
            AVG(response_time_ms) as avg_response_time
        FROM completions
    """)

    overall = cursor.fetchone()

    # Get usage by filetype
    cursor.execute("""
        SELECT
            filetype,
            COUNT(*) as count,
            AVG(CAST(accepted AS FLOAT)) as acceptance_rate
        FROM completions
        GROUP BY filetype
        ORDER BY count DESC
        LIMIT 10
    """)

    filetypes = cursor.fetchall()

    conn.close()

    return {
        'models': models,
        'overall': {
            'total_completions': overall[0] or 0,
            'total_accepted': overall[1] or 0,
            'total_liked': overall[2] or 0,
            'total_disliked': overall[3] or 0,
            'total_cost': overall[4] or 0,
            'avg_response_time': overall[5] or 0,
        },
        'filetypes': [
            {'filetype': ft, 'count': count, 'acceptance_rate': rate or 0}
            for ft, count, rate in filetypes
        ]
    }


def generate_markdown_report(stats: Dict) -> str:
    """Generate markdown report from statistics."""

    report = ["# Autocomplete Model Performance Report\n"]
    report.append(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
    report.append("---\n\n")

    # Overall statistics
    overall = stats['overall']
    report.append("## Overall Statistics\n")
    report.append(f"- **Total Completions:** {overall['total_completions']:,}\n")
    report.append(f"- **Accepted:** {overall['total_accepted']:,} ({overall['total_accepted']/max(overall['total_completions'],1)*100:.1f}%)\n")
    report.append(f"- **Liked:** {overall['total_liked']:,}\n")
    report.append(f"- **Disliked:** {overall['total_disliked']:,}\n")
    report.append(f"- **Total Cost:** ${overall['total_cost']:.4f}\n")
    report.append(f"- **Avg Response Time:** {overall['avg_response_time']:.0f}ms\n\n")

    # Model comparison table
    report.append("## Model Comparison\n\n")
    report.append("| Model | Quality Score | Total Uses | Accepted | Liked | Disliked | Avg Cost | Total Cost | Avg Response Time |\n")
    report.append("|-------|---------------|------------|----------|-------|----------|----------|------------|-------------------|\n")

    for model_data in stats['models']:
        model = model_data['model']
        quality = model_data['quality_score']
        total = model_data['total_completions']
        accepted = model_data['accepted_count']
        liked = model_data['liked_count']
        disliked = model_data['disliked_count']
        avg_cost = model_data['avg_cost']
        total_cost = model_data['total_cost']
        avg_time = model_data['avg_response_time']

        report.append(
            f"| {model} | **{quality:.3f}** | {total} | {accepted} ({accepted/max(total,1)*100:.0f}%) | "
            f"{liked} | {disliked} | ${avg_cost:.6f} | ${total_cost:.4f} | {avg_time:.0f}ms |\n"
        )

    report.append("\n")

    # Quality score explanation
    report.append("## Quality Score Explanation\n\n")
    report.append("Quality score (0-1) is calculated as:\n")
    report.append("- **40%** Acceptance rate (Tab pressed / Total completions)\n")
    report.append("- **40%** Like rate (Ctrl+L pressed / Total reviewed)\n")
    report.append("- **20%** Inverse dislike rate (1 - Ctrl+D pressed / Total reviewed)\n\n")
    report.append("Higher score = Better user satisfaction\n\n")

    # Cost analysis
    report.append("## Cost Analysis\n\n")
    report.append("### Cost for 10,000 Completions\n\n")
    report.append("| Model | Estimated Cost |\n")
    report.append("|-------|----------------|\n")

    for model_data in stats['models']:
        model = model_data['model']
        avg_cost = model_data['avg_cost']
        cost_10k = avg_cost * 10000
        report.append(f"| {model} | **${cost_10k:.2f}** |\n")

    report.append("\n")

    # Usage by filetype
    if stats['filetypes']:
        report.append("## Usage by File Type\n\n")
        report.append("| File Type | Uses | Acceptance Rate |\n")
        report.append("|-----------|------|-----------------|\n")

        for ft_data in stats['filetypes']:
            ft = ft_data['filetype']
            count = ft_data['count']
            rate = ft_data['acceptance_rate']
            report.append(f"| {ft} | {count} | {rate*100:.1f}% |\n")

        report.append("\n")

    # Recommendations
    report.append("## Recommendations\n\n")

    if stats['models']:
        # Find best quality
        best_quality = max(stats['models'], key=lambda x: x['quality_score'])
        # Find cheapest
        cheapest = min(stats['models'], key=lambda x: x['avg_cost'])
        # Find fastest
        fastest = min(stats['models'], key=lambda x: x['avg_response_time'])

        report.append(f"- 🏆 **Highest Quality:** {best_quality['model']} (score: {best_quality['quality_score']:.3f})\n")
        report.append(f"- 💰 **Most Cost-Effective:** {cheapest['model']} (${cheapest['avg_cost']:.6f} per completion)\n")
        report.append(f"- ⚡ **Fastest:** {fastest['model']} ({fastest['avg_response_time']:.0f}ms average)\n")

        # Calculate value score (quality / cost)
        for model_data in stats['models']:
            if model_data['avg_cost'] > 0:
                model_data['value_score'] = model_data['quality_score'] / model_data['avg_cost']
            else:
                model_data['value_score'] = 0

        best_value = max(stats['models'], key=lambda x: x['value_score'])
        report.append(f"- 🎯 **Best Value:** {best_value['model']} (quality/cost ratio: {best_value['value_score']:.0f})\n")

    report.append("\n---\n")
    report.append("\n*Report generated by autocomplete-plugin/analyze.py*\n")

    return ''.join(report)


def main():
    """Main entry point."""
    db_path = get_db_path()

    if not os.path.exists(db_path):
        print(f"Error: Database not found at {db_path}")
        print("Make sure you've used the autocomplete plugin and generated some completions first.")
        return

    print(f"Analyzing database: {db_path}")

    try:
        stats = analyze_database(db_path)

        if stats['overall']['total_completions'] == 0:
            print("\nNo completions found in database yet.")
            print("Use the autocomplete plugin to generate some completions first!")
            return

        # Generate markdown report
        report = generate_markdown_report(stats)

        # Write to file
        report_path = Path(__file__).parent / 'MODEL_COMPARISON.md'
        with open(report_path, 'w') as f:
            f.write(report)

        print(f"\n✓ Report generated: {report_path}")
        print(f"\nTotal completions analyzed: {stats['overall']['total_completions']:,}")
        print(f"Total cost: ${stats['overall']['total_cost']:.4f}")

        # Print summary table
        print("\n" + "="*80)
        print("MODEL COMPARISON SUMMARY")
        print("="*80)
        print(f"{'Model':<40} {'Quality':<10} {'Uses':<8} {'Avg Cost':<12}")
        print("-"*80)
        for model_data in stats['models']:
            print(f"{model_data['model']:<40} {model_data['quality_score']:<10.3f} {model_data['total_completions']:<8} ${model_data['avg_cost']:<11.6f}")
        print("="*80)

    except Exception as e:
        print(f"Error analyzing database: {e}")
        import traceback
        traceback.print_exc()


if __name__ == '__main__':
    main()
