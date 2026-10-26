import os
import sys
import json
import urllib.request
import subprocess

def get_commit_log():
    try:
        # Get the latest tag
        latest_tag = subprocess.check_output(['git', 'describe', '--tags', '--abbrev=0']).decode('utf-8').strip()
        # Get commits since the latest tag
        log = subprocess.check_output(['git', 'log', f'{latest_tag}..HEAD', '--no-merges', '--pretty=format:- %s']).decode('utf-8').strip()
        print(f"Generating notes since {latest_tag}")
        return log
    except Exception:
        # If no tags exist or error, get the last 20 commits
        print("No tags found or error occurred, using last 20 commits.")
        return subprocess.check_output(['git', 'log', '-n', '20', '--no-merges', '--pretty=format:- %s']).decode('utf-8').strip()

def generate_notes(commits, highlights=""):
    api_key = os.getenv("OPENROUTER_API_KEY")
    model_id = os.getenv("OPENROUTER_MODEL", "qwen/qwen3.7-plus")
    print(f"Generating notes using model: {model_id}")
    if not api_key:
        print("Warning: OPENROUTER_API_KEY is not set. Using fallback changelog.")
        return f"### Overview\n\nMaintenance and stability updates.\n\n### Changes\n\n{commits}"

    highlights_context = ""
    if highlights:
        highlights_context = f"\nMaintainer Focus & Highlights:\n{highlights}\n"

    prompt = f"""You are an engineering release manager writing a clear, professional release description for Dicty (a high-performance AI voice dictation and autonomous engineering documentation application for macOS).

Review the following Git commit logs and any maintainer notes to produce human-readable, well-structured release notes in Markdown.
{highlights_context}
Commits:
{commits}

REQUIRED STRUCTURE:
1. Executive Overview / Description:
   - Provide 1 to 3 clear, natural, and human-readable sentences summarizing what this release accomplishes, what key capabilities or fixes were delivered, and how it benefits the user.
   - Do NOT just copy-paste raw commit messages here; synthesize them into a cohesive narrative description.

2. Categorized Changes (only include sections that have items):
   ### Features
   - [bullet points of new user-facing capabilities]

   ### Improvements
   - [bullet points of performance, UX, dependency, or packaging improvements]

   ### Bug Fixes
   - [bullet points of bug fixes and stability improvements]

STRICT GUIDELINES:
- Zero emojis anywhere (clean, professional engineering tone).
- Do not include commit hashes, author usernames, or PR issue numbers.
- Do not add filler greetings or sign-offs (e.g. no "We are excited to announce", no "Happy dictating!").
- Do not invent features or fixes not present in the commits or maintainer context.
"""

    data = {
        "model": model_id,
        "messages": [
            {"role": "system", "content": "You are a professional software release manager. Output a cohesive, human-readable release overview followed by strict technical markdown sections. Zero emojis, zero fluff."},
            {"role": "user", "content": prompt}
        ]
    }
    
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions",
        data=json.dumps(data).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
    )

    try:
        with urllib.request.urlopen(req, timeout=45) as response:
            result = json.loads(response.read().decode())
            return result['choices'][0]['message']['content'].strip()
    except Exception as e:
        print(f"Failed to generate notes via LLM: {e}. Using fallback.")
        return f"### Overview\n\nThis release includes stability, performance, and maintenance updates.\n\n### Changes\n\n{commits}"

if __name__ == "__main__":
    commits = get_commit_log()
    highlights = os.getenv("RELEASE_HIGHLIGHTS", "").strip()
    if not commits and not highlights:
        print("No commits or highlights found.")
        notes = "### Overview\n\nMinor updates, stability improvements, and performance enhancements."
    else:
        notes = generate_notes(commits, highlights)
    
    with open("RELEASE_NOTES.md", "w") as f:
        f.write(notes)
    
    print("Release notes saved to RELEASE_NOTES.md")
