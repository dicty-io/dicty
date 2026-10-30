from fastapi import APIRouter
import threading
from pydantic import BaseModel
from fastapi import HTTPException
from typing import List, Optional
from services.stores import snippets_manager, vocabulary_manager

router = APIRouter()


class PromptUpdateRequest(BaseModel):
    key: str
    value: str

prompts_lock = threading.Lock()

@router.get("/prompts")
def get_prompts():
    from prompts import (
        get_reconcile_system_prompt_default, get_reconcile_system_prompt,
        get_confluence_agent_system_prompt_default, get_confluence_agent_system_prompt,
        get_obsidian_agent_system_prompt_default, get_obsidian_agent_system_prompt,
        get_hub_system_prompt_default, get_hub_system_prompt,
        get_architecture_system_prompt_default, get_architecture_system_prompt,
        get_dictation_custom_system_prompt_default, get_dictation_custom_system_prompt,
        get_dictation_message_system_prompt_default, get_dictation_message_system_prompt,
        get_dictation_email_system_prompt_default, get_dictation_email_system_prompt,
        get_dictation_note_system_prompt_default, get_dictation_note_system_prompt,
        get_dictation_meeting_system_prompt_default, get_dictation_meeting_system_prompt,
        get_dictation_book_system_prompt_default, get_dictation_book_system_prompt,
        get_meeting_summary_system_prompt_default, get_meeting_summary_system_prompt
    )

    
    def get_info(key, default_fn, active_fn, description):
        default_val = default_fn()
        active_val = active_fn()
        return {
            "key": key,
            "description": description,
            "default_value": default_val,
            "active_value": active_val,
            "is_custom": active_val != default_val
        }
        
    return [
        get_info("reconcile_system", get_reconcile_system_prompt_default, get_reconcile_system_prompt, "Used for the legacy direct-LLM update system (non-agent mode)."),
        get_info("confluence_agent_system", get_confluence_agent_system_prompt_default, get_confluence_agent_system_prompt, "Controls how the Librarian agent updates Confluence pages, instructing it to read the current page first."),
        get_info("obsidian_agent_system", get_obsidian_agent_system_prompt_default, get_obsidian_agent_system_prompt, "Controls how the Librarian agent updates Obsidian markdown files, including how it discovers and reads existing notes."),
        get_info("hub_system", get_hub_system_prompt_default, get_hub_system_prompt, "Instructions for auto-updating the main index Hub (like README.md) with links to new documentation pages."),
        get_info("architecture_system", get_architecture_system_prompt_default, get_architecture_system_prompt, "Used when the Librarian explores your GitHub repository to build a comprehensive ARCHITECTURE.md file."),
        get_info("dictation_custom_system", get_dictation_custom_system_prompt_default, get_dictation_custom_system_prompt, "The base style instructions used when you select the 'Custom' dictation formatting mode."),
        get_info("dictation_message_system", get_dictation_message_system_prompt_default, get_dictation_message_system_prompt, "Formats voice dictation into a natural, conversational chat message for Slack, iMessage, etc."),
        get_info("dictation_email_system", get_dictation_email_system_prompt_default, get_dictation_email_system_prompt, "Structures voice dictation into a professional, correctly formatted email with greetings and sign-offs."),
        get_info("dictation_note_system", get_dictation_note_system_prompt_default, get_dictation_note_system_prompt, "Organizes your voice dictation into clean, structured markdown notes with headers and bullet points."),
        get_info("dictation_meeting_system", get_dictation_meeting_system_prompt_default, get_dictation_meeting_system_prompt, "Used in Meeting mode to synthesize raw transcripts into actionable summaries and key decisions."),
        get_info("dictation_book_system", get_dictation_book_system_prompt_default, get_dictation_book_system_prompt, "Refines voice dictation into publication-ready book text with proper paragraphs, dialogue quotes, and punctuation."),
        get_info("meeting_summary_system", get_meeting_summary_system_prompt_default, get_meeting_summary_system_prompt, "Used by the 'Generate Summary' button in History to explicitly summarize any past transcript.")
    ]
@router.put("/prompts")
def update_prompt(req: PromptUpdateRequest):
    import json
    import os
    from prompts import PROMPTS_FILE
    with prompts_lock:
        data = {}
        if os.path.exists(PROMPTS_FILE):
            try:
                with open(PROMPTS_FILE, "r") as f:
                    data = json.load(f)
            except Exception:
                pass
        data[req.key] = req.value
        with open(PROMPTS_FILE, "w") as f:
            json.dump(data, f, indent=4)
    return {"status": "success"}

@router.delete("/prompts/{key}")
def delete_prompt(key: str):
    import json
    import os
    from prompts import PROMPTS_FILE
    with prompts_lock:
        if os.path.exists(PROMPTS_FILE):
            try:
                with open(PROMPTS_FILE, "r") as f:
                    data = json.load(f)
                if key in data:
                    del data[key]
                    with open(PROMPTS_FILE, "w") as f:
                        json.dump(data, f, indent=4)
            except Exception:
                pass
    return {"status": "success"}

class VocabularyItem(BaseModel):
    word: str
    replacement: str

@router.get("/vocabulary")
async def get_vocabulary():
    return {"vocabulary": vocabulary_manager.get_all()}

@router.post("/vocabulary")
async def add_vocabulary(item: VocabularyItem):
    record = vocabulary_manager.add_item({"word": item.word, "replacement": item.replacement})
    return {"status": "success", "item": record}

@router.delete("/vocabulary/{item_id}")
async def delete_vocabulary(item_id: str):
    item = vocabulary_manager.delete_item(item_id)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return {"status": "success", "deleted": item_id}

class LoadDefaultsRequest(BaseModel):
    replace: Optional[bool] = False

@router.post("/vocabulary/defaults")
async def load_default_vocabulary(req: Optional[LoadDefaultsRequest] = None):
    replace = req.replace if req else False
    items = vocabulary_manager.load_defaults(replace=replace)
    return {"status": "success", "vocabulary": items}

class SnippetItem(BaseModel):
    trigger: str
    content: str
    aliases: Optional[List[str]] = None
    expand_anywhere: Optional[bool] = False

@router.get("/snippets")
async def get_snippets():
    return {"snippets": snippets_manager.get_all()}

@router.post("/snippets")
async def add_snippet(item: SnippetItem):
    try:
        record = snippets_manager.add(item.trigger, item.content, item.aliases, bool(item.expand_anywhere))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return {"status": "success", "item": record}

@router.put("/snippets/{item_id}")
async def update_snippet(item_id: str, item: SnippetItem):
    try:
        record = snippets_manager.update(item_id, item.trigger, item.content, item.aliases, bool(item.expand_anywhere))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    if not record:
        raise HTTPException(status_code=404, detail="Snippet not found")
    return {"status": "success", "item": record}

@router.delete("/snippets/{item_id}")
async def delete_snippet(item_id: str):
    if not snippets_manager.delete(item_id):
        raise HTTPException(status_code=404, detail="Snippet not found")
    return {"status": "success", "deleted": item_id}
