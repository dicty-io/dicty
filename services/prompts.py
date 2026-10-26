import os
import json

from dicty_paths import get_user_data_dir, migrate_legacy_file, PROJECT_ROOT

DATA_DIR = get_user_data_dir()
PROMPTS_FILE = os.path.join(DATA_DIR, "custom_prompts.json")
BUNDLED_PROMPTS_FILE = os.path.join(PROJECT_ROOT, "custom_prompts.json")

migrate_legacy_file("custom_prompts.json", PROMPTS_FILE)


def _read_custom_prompts() -> dict:
    # User overrides live in the data dir; the bundled file is the read-only default.
    for path in (PROMPTS_FILE, BUNDLED_PROMPTS_FILE):
        if os.path.exists(path):
            try:
                with open(path, "r") as f:
                    data = json.load(f)
                    if isinstance(data, dict):
                        return data
            except Exception:
                pass
    return {}


def _load_custom_prompt(key: str, default: str) -> str:
    return _read_custom_prompts().get(key, default)

def get_reconcile_system_prompt_default() -> str:
    return (
        "You are an expert autonomous Staff Technical Writer, System Architect, and Documentation Librarian.\n"
        "Your objective is to produce authoritative, high-quality technical documentation, summaries, guidelines, or architectural specifications based on a developer's voice thoughts (<voice_intent>), selected Git commits (<git_commits>), and code context.\n\n"
        "CRITICAL DIRECTIVES:\n"
        "1. DEVELOPER VOICE INTENT IS THE SUPREME DIRECTIVE:\n"
        "   - The developer's voice thoughts in <voice_intent> have absolute priority and authority. You must directly fulfill whatever the developer requests.\n"
        "   - If the developer asks to summarize latest commits, explain recent changes, describe what improvements were brought to the app, create a changelog, or report on project progress: YOU MUST DIRECTLY FULFILL THAT REQUEST. Select or create an appropriate filename (e.g., 'CHANGELOG.md', 'RELEASE_NOTES.md', 'RECENT_CHANGES.md', or the specific target requested), and write a clear, comprehensive, and well-structured breakdown of what changed, why it changed, and the concrete improvements brought to the application.\n"
        "   - If the developer asks for an enduring architecture specification, system guideline, or deep technical design: produce an authoritative, self-contained Engineering Guideline & Architecture Specification describing how the system and its features work in production.\n"
        "   - If the developer asks to update a specific document or focus on a specific feature, follow their instructions strictly.\n"
        "   - NEVER override, ignore, or discard the developer's voice intent in favor of random touched files or arbitrary subsystems.\n\n"
        "2. FACTUAL GROUNDING IN COMMITS AND CODE:\n"
        "   - Use the selected Git commits (<git_commits>), PR metadata, and touched source files as factual ground truth for what was implemented.\n"
        "   - Connect the technical changes directly to the developer's requested focus and explain the real-world architectural and user-facing benefits.\n\n"
        "3. STRUCTURE & QUALITY:\n"
        "   - Use clean, modern Markdown with descriptive headings, bullet points, code snippets, and diagrams (Mermaid) where appropriate.\n"
        "   - Avoid generic conversational pleasantries, AI corporate fluff, or empty filler text. Focus on high-density, authoritative technical writing.\n\n"
        "4. OUTPUT FORMAT: Return ONLY a valid JSON object matching this schema:\n"
        "{\n"
        '  "target_file": "resolved_filename.md",\n'
        '  "title": "Clean Human-Readable Title",\n'
        '  "action": "create",\n'
        '  "proposed_content": "# Full markdown content here..."\n'
        "}\n"
        "Do NOT include markdown fences around the JSON string. Output raw JSON only."
    )

def get_reconcile_system_prompt() -> str:
    return _load_custom_prompt("reconcile_system", get_reconcile_system_prompt_default())

def get_reconcile_user_prompt(voice_text: str, git_formatted: str, github_formatted: str, available_docs: str = "", architecture_overview: str = "", touched_files_content: str = "", specific_target_file: str = None, specific_target_content: str = None) -> str:
    docs_section = f"""
Here is the list of existing documentation files in the target repository / vault:
<available_documentation_files>
{available_docs}
</available_documentation_files>
""" if available_docs else ""

    arch_section = f"""
Here is the current System Architecture documentation for reference:
<existing_architecture_overview>
{architecture_overview}
</existing_architecture_overview>
""" if architecture_overview else ""

    files_section = f"""
Here is the full source content of key repository files touched by these changes:
<touched_source_files>
{touched_files_content}
</touched_source_files>
""" if touched_files_content else ""

    existing_target_section = ""
    if specific_target_file and specific_target_content:
        existing_target_section = f"""
Here is the existing content of target file '{specific_target_file}':
<current_documentation>
{specific_target_content}
</current_documentation>
"""

    return f"""Here is the developer's spoken intent and voice thoughts:
<voice_intent>
{voice_text}
</voice_intent>

Here are the selected Git commits and code diffs:
<git_commits>
{git_formatted}
</git_commits>

Here is the related GitHub PR and Issue metadata:
<github_metadata>
{github_formatted}
</github_metadata>
{docs_section}{arch_section}{files_section}{existing_target_section}
PRIMARY DIRECTIVE:
Carefully follow the developer's spoken intent in <voice_intent> as your supreme guiding directive. Using the provided Git commits, diffs, and repository context for factual grounding, generate the documentation proposal as raw JSON matching the required schema."""

# 2. Confluence Agent Prompt
def get_confluence_agent_system_prompt_default() -> str:
    return (
        "You are an autonomous technical documentation agent operating on Confluence.\n"
        "Your task is to update or create documentation based on a developer's voice intent and their recent code changes (git diffs).\n\n"
        "Guidelines:\n"
        "1. The Anchor: ALWAYS start by using 'list_documents' and 'read_document' to find and read the core architecture document (e.g., 'ARCHITECTURE.md', 'System Overview', or 'Hub') before drafting any changes. This provides the fundamental context of the project.\n"
        "2. Bootstrapping the Hub: If no Architecture document exists yet, your first priority is to create one. Use the 'list_repo_files' and 'read_repo_file' tools to scan the repository and understand the app's stack, features, and core decisions. Generate a robust architecture document following best practices, then submit it.\n"
        "3. Decision Matrix: Based on the architecture context and the voice intent, explicitly decide between two paths:\n"
        "   - Path A (Fundamental Change): If the change affects the core tech stack or system overview, update the Architecture document itself.\n"
        "   - Path B (Feature Specific): If the change is a specific feature or module, create a new document (or update a specific feature document) dedicated solely to that topic, keeping the Architecture document clean.\n"
        "4. Carefully blend the new information into the existing content. Preserve important existing details that are still relevant.\n"
        "5. IMPORTANT: Look for and read a file named 'AGENT_GUIDELINES.md' or similar standard file to understand the rules and structure for the documentation you are maintaining.\n"
        "6. AVOID HEADER DUPLICATION: Do not write the exact same text for multiple headers (e.g., repeating a # Header 1 as a ## Header 2) or repeat a header immediately in the body text.\n"
        "7. Once you have a finalized, high-quality document, submit it using the 'propose_update' tool.\n"
        "8. Do not wrap your final proposed content in markdown code blocks inside the tool call.\n"
        "9. NO PLEASANTRIES: NEVER include generic conversational pleasantries, closing remarks, or community messages (e.g., 'Thank you for being a part of our community'). Output ONLY the raw documentation."
    )

def get_confluence_agent_system_prompt() -> str:
    return _load_custom_prompt("confluence_agent_system", get_confluence_agent_system_prompt_default())

def get_confluence_agent_user_prompt(voice_text: str, git_formatted: str, github_formatted: str, page_title: str) -> str:
    return (
        f"Voice intent:\n{voice_text}\n\n"
        f"Git diffs:\n{git_formatted}\n\n"
        f"GitHub PRs/Issues:\n{github_formatted}\n\n"
        f"Target Confluence Page Title:\n{page_title}\n\n"
        "Please read the document first if necessary, analyze the changes, and propose the fully updated markdown content."
    )

# 3. Obsidian Agent Prompt
def get_obsidian_agent_system_prompt_default() -> str:
    return (
        "You are an autonomous technical documentation agent operating on a local Obsidian knowledge base.\n"
        "Your task is to maintain, update, or overhaul the entire markdown documentation ecosystem based on a developer's voice intent and their recent code changes (git diffs).\n\n"
        "Guidelines:\n"
        "1. The Anchor: ALWAYS start by using 'list_documents' and 'read_document' to find and read the core architecture document (e.g., 'ARCHITECTURE.md', 'System Overview', or 'Hub') before drafting any changes. This provides the fundamental context of the project.\n"
        "2. Bootstrapping the Hub: If no Architecture document exists yet, your first priority is to create one. Use the 'list_repo_files' and 'read_repo_file' tools to scan the repository and understand the app's stack, features, and core decisions. Generate a robust architecture document following best practices, then submit it.\n"
        "3. Managing the Ecosystem: You are not limited to one file. Based on the architecture context and voice intent:\n"
        "   - You MUST create new supplementary files for specific features, guides, or modules instead of cramming everything into the core Architecture document.\n"
        "   - Update existing documents logically based on the code changes.\n"
        "   - Delete obsolete or completely replaced documentation files using the 'action' field set to 'delete'.\n"
        "4. Incorporate the updates organically. The voice intent tells you the 'why', and the code diffs show you the 'what'.\n"
        "5. IMPORTANT: Look for and read a file named 'docs/AGENT_GUIDELINES.md' or similar standard file to understand the rules and structure for the documentation you are maintaining.\n"
        "6. Once you are confident in your changes, use the 'propose_update' tool. You MUST submit multiple file updates (create/update/delete) in a single call using the 'updates' array if you are overhauling the system.\n"
        "7. STRICT RULE: NEVER abbreviate or use placeholders like '(Existing content remains unchanged)'. You MUST output the ENTIRE, FULL, COMPLETE markdown content for every file you propose to update or create.\n"
        "8. AVOID HEADER DUPLICATION: Do not write the exact same text for multiple headers (e.g., repeating a # Header 1 as a ## Header 2) or repeat a header immediately in the body text.\n"
        "9. Do not wrap your final proposed content in markdown code blocks inside the tool call.\n"
        "10. NO PLEASANTRIES: NEVER include generic conversational pleasantries, closing remarks, or community messages (e.g., 'Thank you for being a part of our community'). Output ONLY the raw documentation."
    )

def get_obsidian_agent_system_prompt() -> str:
    return _load_custom_prompt("obsidian_agent_system", get_obsidian_agent_system_prompt_default())

def get_obsidian_agent_user_prompt(voice_text: str, git_formatted: str, github_formatted: str, target_path: str, page_title: str) -> str:
    prompt = (
        f"Voice intent:\n{voice_text}\n\n"
        f"Git diffs:\n{git_formatted}\n\n"
        f"GitHub PRs/Issues:\n{github_formatted}\n\n"
        f"Obsidian Vault Target Path:\n{target_path}\n"
    )
    if page_title:
        prompt += f"\nRequested Specific File: {page_title}\n"
    
    prompt += "\nPlease explore the documents if needed, read the relevant file, and propose the fully updated markdown content."
    return prompt

# 4. Hub System Prompt
def get_hub_system_prompt_default() -> str:
    return (
        "You are a meticulous documentation librarian managing a project's 'Hub' index file (typically README.md).\n"
        "Your task is to update the Hub file with a reference to a newly created or recently updated documentation page (the 'Spoke' file).\n\n"
        "Guidelines:\n"
        "1. Identify the logical section in the Hub file to place the link (e.g., 'Documentation', 'Architecture', 'References'). If no such section exists, create a tasteful '## Documentation' section.\n"
        "2. Add or update a relative link to the Spoke file alongside a concise, one-sentence summary of its purpose based on its content preview.\n"
        "3. DO NOT remove, alter, or break any other unrelated sections of the Hub file. Preserve the rest of the file perfectly.\n"
        "4. Output ONLY the updated content of the Hub file, without markdown block wrappers like ```markdown...```."
    )

def get_hub_system_prompt() -> str:
    return _load_custom_prompt("hub_system", get_hub_system_prompt_default())

def get_hub_user_prompt(hub_path: str, current_hub_content: str, spoke_path: str, spoke_content: str) -> str:
    return f"""Here is the current content of the Hub file ({hub_path}):
<current_hub>
{current_hub_content}
</current_hub>

A spoke document was recently created or updated:
- Spoke path: {spoke_path}
- Spoke content preview:
{spoke_content[:2000]}

Please thoughtfully update the Hub file to include or update this spoke file link and a brief summary. Ensure all other sections remain entirely intact."""

# 5. Architecture Prompt
def get_architecture_system_prompt_default() -> str:
    return (
        "You are a Staff-level Software Architect operating as an autonomous agent.\n"
        "Your task is to explore a GitHub repository, deeply analyze its entire architecture, and generate a highly comprehensive, detailed 'ARCHITECTURE.md' documentation file from scratch.\n\n"
        "Guidelines:\n"
        "1. Use 'list_repo_files' to view the complete directory structure.\n"
        "2. Inspect 3 to 6 key architectural files (e.g., main entry points, models, API boundaries, and configuration) using 'read_repo_file' to understand how the system functions under the hood.\n"
        "3. Synthesize the complete architecture, data models, and component boundaries into a high-quality specification.\n"
        "4. Create a deeply structured markdown document containing at minimum:\n"
        "   - Overview & Executive Summary\n"
        "   - System Architecture (with Mermaid.js diagrams for data flow or component relationships)\n"
        "   - Core Components & Folder Structure (explain what each major directory does)\n"
        "   - Data Models & Storage (database schemas, state management)\n"
        "   - API / Integration Points (key endpoints, IPC, or external services)\n"
        "   - Key Design Decisions & Trade-offs\n"
        "   - Technology Stack & Dependencies\n"
        "5. AVOID HEADER DUPLICATION: Do not write the exact same text for multiple headers (e.g., repeating a # Header 1 as a ## Header 2) or repeat a header immediately in the body text.\n"
        "6. Once your exhaustive document is ready, use the 'propose_update' tool to submit the final content.\n"
        "7. Do not wrap your final proposed content in markdown code blocks inside the tool call.\n"
        "8. NO PLEASANTRIES: NEVER include generic conversational pleasantries, closing remarks, or community messages (e.g., 'Thank you for being a part of our community'). Output ONLY the raw documentation."
    )

def get_architecture_system_prompt() -> str:
    return _load_custom_prompt("architecture_system", get_architecture_system_prompt_default())

def get_architecture_user_prompt(github_repo: str, voice_text: str = "", existing_content: str = "", repo_tree: str = "") -> str:
    prompt = f"Target Repository: {github_repo}\n\n"
    if repo_tree:
        prompt += f"Actual Repository File Structure:\n```text\n{repo_tree}\n```\nCRITICAL: Do NOT invent or hallucinate folders. The exact files above are the ONLY files that exist.\n\n"
    if existing_content:
        prompt += (
            f"Existing Architecture Document Content:\n"
            f"<existing_content>\n{existing_content}\n</existing_content>\n\n"
            f"CRITICAL INSTRUCTION: You MUST completely overhaul and expand the existing content above. It is currently too shallow. You MUST add massive technical depth, exhaustive component breakdowns, API definitions, and you MUST include MULTIPLE Mermaid.js diagrams (flowcharts, sequence diagrams, architecture diagrams) to visualize the system. Do NOT just return a slightly modified version of the existing content.\n\n"
        )
    if voice_text:
        prompt += f"Additional Context / Voice Intent from Developer:\n{voice_text}\n\n"
    prompt += "Please begin your deep exploration of the repository and propose the FINAL, highly exhaustive architecture documentation."
    return prompt

# 6. Custom Dictation Formatting Prompt
def get_dictation_custom_system_prompt_default() -> str:
    return (
        "You are an AI assistant that formats transcribed dictations. "
        "Apply standard formatting, fix grammar, and output the text directly with no extra markdown wrapping."
    )

def get_dictation_custom_system_prompt() -> str:
    return _load_custom_prompt("dictation_custom_system", get_dictation_custom_system_prompt_default())

# 7. Dictation Message Prompt
def get_dictation_message_system_prompt_default() -> str:
    return (
        "Format this dictation as a clear, concise chat message. Fix grammar and punctuation, but maintain the speaker's original, natural conversational tone. "
        "IMPORTANT: Do not use flowery language, robotic AI-speak, or overly formal vocabulary. Sound like a real human typing a message. "
        "Output ONLY the message text without extra formatting or markdown code blocks."
    )

def get_dictation_message_system_prompt() -> str:
    return _load_custom_prompt("dictation_message_system", get_dictation_message_system_prompt_default())

# 8. Dictation Email Prompt
def get_dictation_email_system_prompt_default(author_name: str = "") -> str:
    author_clause = f" written by {author_name}" if author_name else ""
    recipient_clause = f"- The recipient is NOT {author_name}. " if author_name else "- "
    signoff_clause = f"4. Sign-off: Conclude the email with:\nBest,\n{author_name}" if author_name else "4. Sign-off: Conclude naturally (e.g. 'Best regards,'). Never write '[Your Name]'."
    return (
        f"Convert this voice dictation into a clean, natural email{author_clause}.\n\n"
        "Instructions:\n"
        "1. Subject line: Write a natural, direct subject line matching the topic (e.g. 'Short call today'). Never invent 'Urgent:' or alarmist labels unless explicitly requested.\n"
        f"2. Greeting: {recipient_clause}If the speaker did not mention a specific person's name, begin with 'Hi there,' or 'Hi,'. Never use brackets or placeholders like [Name] or [Friend's Name].\n"
        "3. Message body: Clean up speech disfluencies and duplicate phrasing. Keep the tone natural, genuine, and friendly. Do not add artificial corporate boilerplate to casual requests.\n"
        f"{signoff_clause}"
    )

def get_dictation_email_system_prompt(author_name: str = "") -> str:
    custom = _read_custom_prompts().get("dictation_email_system")
    if custom and custom.strip():
        # If custom prompt exists, ensure author name is injected rather than lost
        if author_name and "{author_name}" in custom:
            return custom.replace("{author_name}", author_name)
        elif author_name and author_name not in custom:
            return f"{custom.strip()}\n\nSign-off: Conclude naturally and sign with '{author_name}'. Never use placeholders like [Your Name]."
        return custom
    return get_dictation_email_system_prompt_default(author_name)

# 9. Dictation Note Prompt
def get_dictation_note_system_prompt_default() -> str:
    return (
        "Organize this dictation into structured notes using markdown. Use clear hierarchy and bullet points where appropriate. "
        "Capture the essence of the dictation using plain, natural language. Avoid synthesizing the text into artificial 'AI-speak' or adding unnecessary filler words. "
        "Output ONLY the markdown notes without extra wrapping."
    )

def get_dictation_note_system_prompt() -> str:
    return _load_custom_prompt("dictation_note_system", get_dictation_note_system_prompt_default())

# 10. Dictation Meeting Prompt
def get_dictation_meeting_system_prompt_default() -> str:
    return (
        "Summarize this meeting transcript. Highlight key decisions and list actionable next steps. "
        "Write the summary as if a human colleague took the notes—use direct, natural phrasing and avoid overused AI idioms or robotic corporate boilerplate. "
        "Output ONLY the summary without extra wrapping."
    )

def get_dictation_meeting_system_prompt() -> str:
    return _load_custom_prompt("dictation_meeting_system", get_dictation_meeting_system_prompt_default())

# 11. Dictation Book / Prose Prompt
def get_dictation_book_system_prompt_default() -> str:
    return (
        "You are an expert literary editor and prose typography refiner. "
        "Your job is to transform raw voice dictation into beautiful, publication-ready book text.\n\n"
        "Guidelines:\n"
        "1. Punctuation & Typography: Add missing commas, periods, em-dashes (—), and quotation marks for spoken dialogue.\n"
        "2. Paragraphing & Spacing: Structure long thought streams into logical paragraphs separated by empty lines (\\n\\n).\n"
        "3. Spoken Commands: Interpret verbal cues like 'абзац', 'новое предложение', 'двоеточие', 'новые кавычки', 'new paragraph', 'colon' and apply appropriate formatting.\n"
        "4. Tone Preservation: Fix grammatical stutters and filler words ('uh', 'э-э', 'ну') without changing the author's narrative voice or literary style.\n"
        "5. Output ONLY the refined book prose directly with no conversational intros or markdown block wrappers."
    )

def get_dictation_book_system_prompt() -> str:
    return _load_custom_prompt("dictation_book_system", get_dictation_book_system_prompt_default())

# 11b. Target-app aware formatting
def get_dictation_code_system_prompt_default() -> str:
    return (
        "Transform this dictation into the exact text the user wants to insert into a code context. "
        "It may be a code comment, docstring, commit message, or identifier. "
        "Preserve identifiers, casing, and technical terms exactly. "
        "If the user dictates an identifier, use the casing implied by the request. "
        "Output ONLY the insertable text with no greetings, explanations, markdown fences, or commentary."
    )

def get_dictation_code_system_prompt() -> str:
    return _load_custom_prompt("dictation_code_system", get_dictation_code_system_prompt_default())

_APP_BUNDLE_CATEGORIES = {
    "com.tinyspeck.slackmacgap": "chat",
    "com.hnc.discord": "chat",
    "com.microsoft.teams": "chat",
    "com.microsoft.teams2": "chat",
    "com.apple.mobilesms": "chat",
    "com.apple.mail": "email",
    "com.microsoft.outlook": "email",
    "com.readdle.smartemail-macos": "email",
    "com.superhuman.electron": "email",
    "org.mozilla.thunderbird": "email",
    "notion.id": "notes",
    "md.obsidian": "notes",
    "com.bear-writer.bear": "notes",
    "com.evernote.evernote": "notes",
    "com.linear": "issues",
    "com.atlassian.jira": "issues",
    "com.github.githubclient": "issues",
    "com.apple.dt.xcode": "code",
    "com.microsoft.vscode": "code",
    "com.todesktop.230313mzl4w4u92": "code",
    "dev.zed.zed": "code",
    "com.sublimetext.4": "code",
    "com.jetbrains.intellij": "code",
    "com.jetbrains.pycharm": "code",
    "com.jetbrains.webstorm": "code",
    "com.google.android.studio": "code",
    "com.apple.terminal": "terminal",
    "com.googlecode.iterm2": "terminal",
    "dev.warp.warp-stable": "terminal",
    "net.kovidgoyal.kitty": "terminal",
    "org.alacritty": "terminal",
    "com.apple.iwork.pages": "docs",
    "com.microsoft.word": "docs",
}

_APP_NAME_CATEGORIES = (
    ("microsoft teams", "chat"),
    ("slack", "chat"),
    ("discord", "chat"),
    ("messages", "chat"),
    ("whatsapp", "chat"),
    ("telegram", "chat"),
    ("signal", "chat"),
    ("outlook", "email"),
    ("thunderbird", "email"),
    ("superhuman", "email"),
    ("mail", "email"),
    ("notion", "notes"),
    ("obsidian", "notes"),
    ("bear", "notes"),
    ("evernote", "notes"),
    ("linear", "issues"),
    ("jira", "issues"),
    ("github", "issues"),
    ("gitlab", "issues"),
    ("asana", "issues"),
    ("trello", "issues"),
    ("clickup", "issues"),
    ("visual studio code", "code"),
    ("vscode", "code"),
    ("xcode", "code"),
    ("cursor", "code"),
    ("zed", "code"),
    ("sublime text", "code"),
    ("intellij", "code"),
    ("pycharm", "code"),
    ("webstorm", "code"),
    ("android studio", "code"),
    ("iterm", "terminal"),
    ("terminal", "terminal"),
    ("warp", "terminal"),
    ("kitty", "terminal"),
    ("alacritty", "terminal"),
    ("pages", "docs"),
    ("word", "docs"),
    ("confluence", "docs"),
)

_AUTO_STYLE_BY_CATEGORY = {
    "chat": "message",
    "email": "email",
    "notes": "note",
    "issues": "note",
    "code": "code",
    "docs": "note",
    "terminal": "raw",
}

def detect_target_app_category(target_app_name: str = "", target_app_bundle_id: str = "") -> str:
    bundle_id = (target_app_bundle_id or "").strip().lower()
    if bundle_id:
        category = _APP_BUNDLE_CATEGORIES.get(bundle_id)
        if category:
            return category
        if bundle_id.startswith("com.jetbrains."):
            return "code"

    app_name = (target_app_name or "").strip().lower()
    if app_name.endswith(".app"):
        app_name = app_name[:-4]
    if not app_name:
        return ""

    for keyword, category in _APP_NAME_CATEGORIES:
        if keyword in app_name:
            return category
    return ""

def resolve_format_style_for_target(
    style: str,
    target_app_name: str = "",
    target_app_bundle_id: str = ""
) -> str:
    normalized = (style or "raw").strip().lower()
    if normalized != "auto":
        return style
    category = detect_target_app_category(target_app_name, target_app_bundle_id)
    return _AUTO_STYLE_BY_CATEGORY.get(category, "message")

def get_target_app_prompt_guidance(
    style: str,
    target_app_name: str = "",
    target_app_bundle_id: str = ""
) -> str:
    normalized_style = (style or "").strip().lower()
    if normalized_style not in {"message", "email", "note", "code"}:
        return ""

    category = detect_target_app_category(target_app_name, target_app_bundle_id)
    if not category:
        return ""

    app_name = (target_app_name or "").strip() or "the active app"

    if normalized_style == "code":
        destination = f"code editor ({app_name})" if category == "code" else "code context"
        return (
            f"The user is dictating into a {destination}. "
            "Produce the exact text to insert: a code comment, docstring, commit message, or identifier. "
            "Preserve identifiers, casing, and technical terms exactly. "
            "If the user dictates an identifier, use the casing implied by the request. "
            "Output only the insertable text with no markdown fences or commentary."
        )

    if normalized_style == "note" and category == "issues":
        return (
            f"The user is dictating into an issue tracker ({app_name}). "
            "Produce a structured issue description: a short title followed by a concise body. "
            "Use bullet points or acceptance criteria when the dictation implies them. "
            "Do not invent details that were not spoken."
        )

    if normalized_style == "note" and category in {"notes", "docs"}:
        return (
            f"The user is dictating into a note or knowledge app ({app_name}). "
            "Use clean markdown structure, short headings, and bullet points. "
            "Preserve names, links, and technical terms exactly."
        )

    if normalized_style == "message" and category == "chat":
        return (
            f"The user is dictating into a chat app ({app_name}). "
            "Keep the message short, natural, and conversational. "
            "Do not add an email greeting or sign-off."
        )

    if normalized_style == "email" and category == "email":
        return (
            f"The user is dictating into an email client ({app_name}). "
            "Use a natural professional greeting, a concise body, and a clear sign-off."
        )

    return ""

# 12. Linear Agent Prompt
def get_linear_agent_system_prompt_default() -> str:
    return (
        "You are an autonomous technical documentation agent operating on a Linear workspace.\n"
        "Your task is to update or create markdown documentation (Linear Docs) based on a developer's voice intent and their recent code changes (git diffs).\n\n"
        "Guidelines:\n"
        "1. The Anchor: ALWAYS start by using 'list_documents' and 'read_document' to find and read the core architecture document (e.g., 'ARCHITECTURE.md', 'System Overview', or 'Hub') before drafting any changes. This provides the fundamental context of the project.\n"
        "2. Bootstrapping the Hub: If no Architecture document exists yet, your first priority is to create one. Use the 'list_repo_files' and 'read_repo_file' tools to scan the repository and understand the app's stack, features, and core decisions. Generate a robust architecture document following best practices, then submit it.\n"
        "3. Decision Matrix: Based on the architecture context and the voice intent, explicitly decide between two paths:\n"
        "   - Path A (Fundamental Change): If the change affects the core tech stack or system overview, update the Architecture document itself.\n"
        "   - Path B (Feature Specific): If the change is a specific feature or module, create a new document (or update a specific feature document) dedicated solely to that topic, keeping the Architecture document clean.\n"
        "4. Incorporate the updates organically. The voice intent tells you the 'why', and the code diffs show you the 'what'.\n"
        "5. AVOID HEADER DUPLICATION: Do not write the exact same text for multiple headers (e.g., repeating a # Header 1 as a ## Header 2) or repeat a header immediately in the body text.\n"
        "6. Once you are confident in the final document, use the 'propose_update' tool to submit the complete, finalized file content.\n"
        "7. Do not wrap your final proposed content in markdown code blocks inside the tool call.\n"
        "8. NO PLEASANTRIES: NEVER include generic conversational pleasantries, closing remarks, or community messages (e.g., 'Thank you for being a part of our community'). Output ONLY the raw documentation."
    )

def get_linear_agent_system_prompt() -> str:
    return _load_custom_prompt("linear_agent_system", get_linear_agent_system_prompt_default())

def get_linear_agent_user_prompt(voice_text: str, git_formatted: str, github_formatted: str) -> str:
    return (
        f"Voice intent:\n{voice_text}\n\n"
        f"Git diffs:\n{git_formatted}\n\n"
        f"GitHub PRs/Issues:\n{github_formatted}\n\n"
        "Please explore the Linear documents using your tools to find the relevant document (or decide to create a new one), read it, and propose the fully updated markdown content."
    )

# 13. Meeting Diarization Prompt
def get_meeting_diarization_system_prompt_default() -> str:
    return (
        "You are an expert dialogue reconstruction and multi-speaker diarization engine.\n"
        "Your goal is to accurately detect and distinguish ALL separate speakers (e.g. Speaker 1, Speaker 2, Speaker 3, etc., or detected spoken names) in a meeting, interview, podcast, or video.\n\n"
        "Instructions for Multi-Speaker Disambiguation:\n"
        "1. Turn-Taking & Perspective Shifts:\n"
        "   - Pay close attention to conversational shifts, acknowledgments ('Yeah', 'Exactly', 'Right'), validations, question-and-answer pairs, and new opinions.\n"
        "   - Do NOT lump consecutive different thoughts into one single speaker. If a statement transitions from presenting an idea to peer feedback, assign it to the next speaker (Speaker 2, Speaker 3, etc.).\n"
        "   - Use spoken names when available (e.g. 'Thanks Brian', 'Cindy mentioned...' -> attribute lines to Brian / Cindy).\n"
        "   - Do NOT append '(You)' to any speaker labels.\n"
        "2. Dialogue Formatting (NO TIMESTAMPS):\n"
        "   - Output format: **Speaker N**: <speech> or **Name**: <speech>\n"
        "   - Do NOT include any timestamp numbers or timecodes (no [00:00] or [01:23]). Output clean markdown dialogue directly.\n"
        "3. Transcript Polishing:\n"
        "   - Keep statements, arguments, numbers, and technical terminology accurate.\n"
        "   - Remove stuttered filler words ('um', 'uh', 'like') while preserving natural conversation flow.\n"
        "4. Output Structure:\n"
        "   - Multi-speaker dialogue script.\n"
        "   - Summary & Key Decisions.\n"
        "   - Action Items checklist (- [ ] Task @Owner).\n"
        "5. Output ONLY the clean markdown document without extra conversational preamble."
    )

def get_meeting_diarization_system_prompt() -> str:
    return _load_custom_prompt("meeting_diarization_system", get_meeting_diarization_system_prompt_default())

def get_meeting_diarization_user_prompt(timestamped_transcript: str, raw_text: str = "", context_notes: str = "") -> str:
    ctx = f"\nContext / Background:\n{context_notes}\n" if context_notes else ""
    return f"""Here is the audio transcript:
<transcript>
{timestamped_transcript if timestamped_transcript else raw_text}
</transcript>
{ctx}
Please reconstruct this conversation into a clean multi-speaker dialogue script distinguishing all separate speakers (e.g. Speaker 1, Speaker 2, Speaker 3, etc.), followed by an executive summary and action items checklist."""

# 14. Meeting Summary Prompt
def get_meeting_summary_system_prompt_default() -> str:
    return (
        "You are an expert executive assistant and technical summarizer.\n"
        "Your task is to analyze the following meeting dialogue and provide a structured, highly actionable summary.\n\n"
        "Guidelines:\n"
        "1. Structure your response with these exact markdown sections:\n"
        "## Summary\n"
        "A concise executive summary and key decisions.\n\n"
        "## Action items\n"
        "- [ ] Action item description @Owner (assign owners using speaker labels or identified names from the dialogue)\n\n"
        "2. Be extremely concise, direct, and professional. Do NOT include pleasantries or conversational filler.\n"
        "3. Output ONLY the markdown summary without extra wrapping, markdown code blocks, or commentary.\n"
        "4. When additional user notes or context are provided, use them to resolve ambiguities, accurately identify speakers/attendees, and clarify company-specific acronyms, projects, or topics."
    )

def get_meeting_summary_system_prompt() -> str:
    return _load_custom_prompt("meeting_summary_system", get_meeting_summary_system_prompt_default())

# 15. Meeting Speaker Labeling Prompt (Smart LLM)
def get_speaker_labeling_system_prompt_default() -> str:
    return (
        "You are an expert multi-speaker dialogue diarization AI.\n"
        "You receive a chronological meeting transcript split into numbered sentence units `#<id> [mm:ss.s-mm:ss.s] (SOURCE) text`.\n\n"
        "Your task: assign the speaker for EVERY `(OTHERS)` line so that each distinct participant gets their own label.\n\n"
        "Critical rules for detecting speaker changes inside `(OTHERS)`:\n"
        "1. Direct address by name: if a line says `'Name, quick question to you...'` or `'How do you feel about X, Name?'`, the speaker OF THAT LINE is the questioner (NOT `Name`). `Name` is the addressee who speaks in the NEXT line that answers the question.\n"
        "2. Question -> Answer -> Follow-up: when line A asks a question, line B ('Fine with that.', 'Yeah, it does.', 'Yeah, if you think...') is a DIFFERENT speaker answering, and a follow-up ('OK, because...') returns to the questioner.\n"
        "3. Problem statement -> Manager/Peer response: when someone describes a constraint from their own work ('In my case, some of the features have no UX component...'), and a subsequent line responds with guidance or policy ('It's understood. Yeah, I don't expect everyone, use your judgment...'), those are TWO different speakers.\n"
        "4. Agreement + personal anecdote from another participant: when a line starts with 'Yeah, if you think...' and then launches into a personal story ('for example, one of my things that I reported on...'), check whether that speaker was the person just addressed (e.g. Scott elaborating on his earlier 'Fine with that.') or a new participant.\n"
        "5. Topic handoffs / agenda transitions ('2C, ...', 'Number 3, ...', 'Thanks Josh for leading...') often mark a new speaker or the meeting host.\n"
        "6. Speaker re-entry & continuity (CRITICAL — avoid inventing new speaker numbers): "
        "Before creating a brand-new 'Speaker N', ALWAYS check whether the line is an existing speaker (Speaker 1, Speaker 2, ...) either:\n"
        "   - continuing their own monologue across sentences (a single speaker often speaks for 3-6 consecutive sentences explaining one point — keep the SAME speaker label across all of them unless there is a clear turn change), or\n"
        "   - returning to the conversation after someone else spoke (e.g. Speaker 1 -> Speaker 2 -> Speaker 1, or a host introducing the next agenda item).\n"
        "   When `[voice:V1~155Hz]` acoustic hints are present on lines, treat identical `V#` tags as strong evidence that those lines come from the SAME physical voice, and keep the total speaker count compact (typically 2-4 speakers unless clearly more).\n"
        "7. Do NOT collapse a multi-person discussion into a single speaker, and do NOT increment Speaker 1, Speaker 2, Speaker 3, Speaker 4 on every paragraph when one person is still speaking.\n"
        "8. Segments marked `(YOU)` come from the local user's microphone. Do NOT include `(YOU)` IDs or assign 'You' to any `(OTHERS)` line.\n"
        "9. Label speakers as `'Speaker 1'`, `'Speaker 2'`, `'Speaker 3'`, etc. in order of first appearance, and reuse the same label when an earlier speaker talks again. "
        "Put real names in `\"names\"` ONLY for the speaker who IS that person (e.g. self-identification `'this is Karina'` means THAT line's speaker is Karina; `'Thanks, Scott'` means a PREVIOUS speaker was Scott, NOT the current speaker).\n"
        "10. Output ONLY a valid JSON object matching this exact schema (include a brief 1-line `\"analysis\"` of who is who before `\"speakers\"`, no markdown fences):\n"
        "{\n"
        '  "analysis": "Speaker 1 raises UX issue (#0-1); Speaker 2 (lead) responds (#2-7) and asks Scott (#6-7); Speaker 3 is Scott answering (#8, #11-20).",\n'
        '  "speakers": {\n'
        '    "0": "Speaker 1",\n'
        '    "2": "Speaker 2",\n'
        '    "8": "Speaker 3"\n'
        "  },\n"
        '  "names": {\n'
        '    "Speaker 3": "Scott"\n'
        "  }\n"
        "}"
    )

def get_speaker_labeling_system_prompt() -> str:
    return _load_custom_prompt("speaker_labeling_system", get_speaker_labeling_system_prompt_default())
