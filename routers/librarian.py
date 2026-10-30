from fastapi import APIRouter
import asyncio
import httpx
import json
import os
import re
from pydantic import BaseModel
from fastapi import HTTPException
from typing import List, Optional
from services.paths import ORCHESTRATOR_URL
from services.state import git
from queue_manager import queue_manager
from services.status import set_status

router = APIRouter()


@router.get("/librarian/queue")
async def get_librarian_queue():
    return {
        "status": "success",
        "items": queue_manager.list_items(),
        "count": queue_manager.count()
    }

class AddQueueItemRequest(BaseModel):
    text: str
    source: Optional[str] = "manual"

@router.post("/librarian/queue")
async def add_librarian_queue_item(req: AddQueueItemRequest):
    if not req.text.strip():
        raise HTTPException(status_code=400, detail="Text cannot be empty")
    branch_name = ""
    commit_sha = ""
    try:
        branch_name = git.repo.active_branch.name
        commit_sha = git.repo.head.commit.hexsha[:7]
    except Exception:
        pass
    item = queue_manager.add_item(
        text=req.text,
        source=req.source,
        git_branch=branch_name,
        git_commit=commit_sha
    )
    return {"status": "success", "item": item, "count": queue_manager.count()}

class UpdateQueueItemRequest(BaseModel):
    text: str

@router.put("/librarian/queue/{item_id}")
async def update_librarian_queue_item(item_id: str, req: UpdateQueueItemRequest):
    if not req.text.strip():
        raise HTTPException(status_code=400, detail="Text cannot be empty")
    updated = queue_manager.update_item(item_id, req.text)
    if not updated:
        raise HTTPException(status_code=404, detail="Item not found")
    return {"status": "success", "item": updated}

@router.delete("/librarian/queue/{item_id}")
async def delete_librarian_queue_item(item_id: str):
    success = queue_manager.delete_item(item_id)
    return {"status": "success", "deleted": success, "count": queue_manager.count()}

@router.delete("/librarian/queue")
async def clear_librarian_queue():
    queue_manager.clear()
    return {"status": "success", "count": 0}

class SynthesizeQueueRequest(BaseModel):
    thoughts: Optional[List[str]] = None
    target_type: Optional[str] = "local" # local, obsidian, confluence, linear
    target_file: Optional[str] = "docs/ARCHITECTURE.md"
    obsidian_path: Optional[str] = ""
    confluence_url: Optional[str] = ""
    confluence_space: Optional[str] = ""
    confluence_user: Optional[str] = ""
    confluence_token: Optional[str] = ""
    confluence_page_title: Optional[str] = ""
    linear_api_token: Optional[str] = ""
    linear_workspace_id: Optional[str] = ""
    linear_search_all: Optional[bool] = False
    notion_api_key: Optional[str] = ""
    notion_page_id: Optional[str] = ""
    git_provider: Optional[str] = "github"
    github_token: Optional[str] = ""
    github_repo: Optional[str] = ""
    gitlab_host: Optional[str] = "https://gitlab.com"
    gitlab_token: Optional[str] = ""
    gitlab_repo: Optional[str] = ""
    bitbucket_token: Optional[str] = ""
    bitbucket_repo: Optional[str] = ""
    github_prs: Optional[str] = ""
    github_commits: Optional[str] = ""
    llm_provider: Optional[str] = "openrouter"
    llm_base_url: Optional[str] = ""
    llm_model: Optional[str] = "qwen/qwen3.7-plus"
    llm_api_key: Optional[str] = ""
    custom_prompt: Optional[str] = ""
    clear_queue_on_success: Optional[bool] = False

@router.post("/librarian/synthesize")
async def synthesize_librarian_docs(req: SynthesizeQueueRequest):
    items = queue_manager.list_items()
    thought_texts = req.thoughts if req.thoughts is not None else [i.get("text", "") for i in items if i.get("text")]
    if not thought_texts:
        return {"status": "error", "message": "No thoughts in queue to synthesize. Record some thoughts first."}

    combined_thoughts = "\n\n".join([
        f"--- [Recorded Thought {idx+1}] ---\n{text}"
        for idx, text in enumerate(thought_texts)
    ])
    
    commits = []
    if req.github_commits:
        commits = [c.strip() for c in req.github_commits.split(",") if c.strip()]
    else:
        try:
            commits = [git.repo.head.commit.hexsha]
        except Exception:
            commits = []
            
    prs = []
    if req.github_prs:
        prs = [int(p.strip()) for p in req.github_prs.split(",") if p.strip().isdigit()]

    obsidian_path = req.obsidian_path or os.getenv("OBSIDIAN_VAULT_PATH", "")
    llm_provider = req.llm_provider or os.getenv("LLM_PROVIDER", "openrouter")
    if llm_provider == "dicty_cloud":
        llm_api_key = req.llm_api_key or ""
        # If model is not set, or is an OpenRouter :free tier / legacy model, route to fast managed model
        if not req.llm_model or req.llm_model.endswith(":free") or req.llm_model in ["qwen/qwen-3.5-flash", "qwen/qwen3.7-plus"]:
            llm_model = "openai/gpt-4o-mini"
        else:
            llm_model = req.llm_model
    else:
        llm_api_key = req.llm_api_key or os.getenv("OPENROUTER_API_KEY", "") or os.getenv("LLM_API_KEY", "")
        llm_model = req.llm_model or os.getenv("LLM_MODEL", "qwen/qwen3.7-plus")
    git_provider = req.git_provider or "github"
    github_token = req.github_token or os.getenv("GITHUB_TOKEN", "")
    github_repo = req.github_repo or os.getenv("GITHUB_REPO", "")
    gitlab_host = (req.gitlab_host or "https://gitlab.com").rstrip("/")
    if gitlab_host == "https://gitlab.com":
        gitlab_token = req.gitlab_token or os.getenv("GITLAB_TOKEN", "")
    else:
        gitlab_token = req.gitlab_token or ""
    gitlab_repo = req.gitlab_repo or os.getenv("GITLAB_REPO", "")
    bitbucket_token = req.bitbucket_token or os.getenv("BITBUCKET_TOKEN", "")
    bitbucket_repo = req.bitbucket_repo or os.getenv("BITBUCKET_REPO", "")

    url = None
    payload = {}
    if req.target_type == "obsidian" and obsidian_path:
        payload = {
            "voice_text": combined_thoughts,
            "commits": commits,
            "obsidian_path": obsidian_path,
            "page_title": req.confluence_page_title or "",
            "git_provider": git_provider,
            "github_token": github_token,
            "github_repo": github_repo,
            "gitlab_host": gitlab_host,
            "gitlab_token": gitlab_token,
            "gitlab_repo": gitlab_repo,
            "bitbucket_token": bitbucket_token,
            "bitbucket_repo": bitbucket_repo,
            "prs": prs,
            "llm_provider": llm_provider,
            "llm_base_url": req.llm_base_url,
            "llm_model": llm_model,
            "llm_api_key": llm_api_key
        }
        url = f"{ORCHESTRATOR_URL}/reconcile/obsidian"
    elif req.target_type == "confluence" and req.confluence_url and req.confluence_space:
        payload = {
            "voice_text": combined_thoughts,
            "commits": commits,
            "confluence_url": req.confluence_url,
            "space_key": req.confluence_space,
            "user_email": req.confluence_user,
            "api_token": req.confluence_token,
            "page_title": req.confluence_page_title,
            "git_provider": git_provider,
            "github_token": github_token,
            "github_repo": github_repo,
            "gitlab_host": gitlab_host,
            "gitlab_token": gitlab_token,
            "gitlab_repo": gitlab_repo,
            "bitbucket_token": bitbucket_token,
            "bitbucket_repo": bitbucket_repo,
            "prs": prs,
            "llm_provider": llm_provider,
            "llm_base_url": req.llm_base_url,
            "llm_model": llm_model,
            "llm_api_key": llm_api_key
        }
        url = f"{ORCHESTRATOR_URL}/reconcile/confluence"
    elif req.target_type == "linear" and req.linear_api_token:
        payload = {
            "voice_text": combined_thoughts,
            "commits": commits,
            "linear_api_token": req.linear_api_token,
            "linear_workspace_id": req.linear_workspace_id or "",
            "search_all": req.linear_search_all,
            "git_provider": git_provider,
            "github_token": github_token,
            "github_repo": github_repo,
            "gitlab_host": gitlab_host,
            "gitlab_token": gitlab_token,
            "gitlab_repo": gitlab_repo,
            "bitbucket_token": bitbucket_token,
            "bitbucket_repo": bitbucket_repo,
            "prs": prs,
            "llm_provider": llm_provider,
            "llm_base_url": req.llm_base_url,
            "llm_model": llm_model,
            "llm_api_key": llm_api_key
        }
        url = f"{ORCHESTRATOR_URL}/reconcile/linear"
    elif req.target_type == "notion":
        notion_key = req.notion_api_key or os.getenv("NOTION_API_KEY", "")
        notion_page = req.notion_page_id or os.getenv("NOTION_PAGE_ID", "")
        payload = {
            "voice_text": combined_thoughts,
            "commits": commits,
            "notion_api_key": notion_key,
            "notion_page_id": notion_page,
            "page_title": req.confluence_page_title or "Architecture Overview",
            "git_provider": git_provider,
            "github_token": github_token,
            "github_repo": github_repo,
            "gitlab_host": gitlab_host,
            "gitlab_token": gitlab_token,
            "gitlab_repo": gitlab_repo,
            "bitbucket_token": bitbucket_token,
            "bitbucket_repo": bitbucket_repo,
            "prs": prs,
            "llm_provider": llm_provider,
            "llm_base_url": req.llm_base_url,
            "llm_model": llm_model,
            "llm_api_key": llm_api_key
        }
        url = f"{ORCHESTRATOR_URL}/reconcile/notion"
    else:
        payload = {
            "voice_text": combined_thoughts,
            "commits": commits,
            "target_file": req.target_file or "docs/ARCHITECTURE.md",
            "git_provider": git_provider,
            "github_token": github_token,
            "github_repo": github_repo,
            "gitlab_host": gitlab_host,
            "gitlab_token": gitlab_token,
            "gitlab_repo": gitlab_repo,
            "bitbucket_token": bitbucket_token,
            "bitbucket_repo": bitbucket_repo,
            "prs": prs,
            "llm_provider": llm_provider,
            "llm_base_url": req.llm_base_url,
            "llm_model": llm_model,
            "llm_api_key": llm_api_key
        }
        url = f"{ORCHESTRATOR_URL}/reconcile"

    try:
        set_status("Synthesizing Architecture Documentation (LLM)...")
        
        # 1. Discover all available documentation in target directory / vault
        available_docs_list = []
        configured_vault = os.getenv("OBSIDIAN_VAULT_PATH", "")
        # Treat user input as a relative path inside the configured vault.
        # This prevents absolute paths from escaping the trusted root.
        if req.target_type == "obsidian" and configured_vault:
            vault_root = os.path.realpath(configured_vault)
            requested_subpath = (req.obsidian_path or "").strip().lstrip("/\\")
            candidate_path = os.path.realpath(os.path.join(vault_root, requested_subpath)) if requested_subpath else vault_root
            try:
                if os.path.commonpath([vault_root, candidate_path]) == vault_root:
                    doc_dir = candidate_path
                else:
                    doc_dir = vault_root
            except (ValueError, OSError):
                doc_dir = vault_root
            obsidian_path = doc_dir
        else:
            doc_dir = os.path.realpath("docs")
            
        if os.path.exists(doc_dir):
            try:
                for root, dirs, files in os.walk(doc_dir):
                    if ".git" in dirs: dirs.remove(".git")
                    for f in files:
                        if f.endswith(".md"):
                            rel = os.path.relpath(os.path.join(root, f), doc_dir)
                            available_docs_list.append(rel)
            except Exception:
                pass
        available_docs_str = "\n".join([f"- {d}" for d in available_docs_list[:40]])

        # 2. Check if a specific target was explicitly requested
        target_path = None
        current_content = None
        if req.target_file and req.target_file not in ["docs/ARCHITECTURE.md", "ARCHITECTURE.md"]:
            safe_basename = os.path.basename(req.target_file.strip())
            # Allow only simple markdown filenames to prevent user-controlled path expressions
            if re.fullmatch(r"[A-Za-z0-9._-]+\.md", safe_basename):
                candidate_path = os.path.realpath(os.path.join(doc_dir, safe_basename))
                try:
                    if os.path.commonpath([doc_dir, candidate_path]) == doc_dir and os.path.exists(candidate_path):
                        target_path = candidate_path
                        with open(target_path, "r", encoding="utf-8", errors="replace") as f:
                            current_content = f.read()
                except Exception:
                    pass

        # Read existing system architecture doc for holistic context
        architecture_overview = ""
        arch_candidates = [
            os.path.join(doc_dir, "ARCHITECTURE.md"),
            os.path.join(doc_dir, "architecture.md"),
            os.path.realpath("docs/ARCHITECTURE.md"),
        ]
        for ac in arch_candidates:
            real_ac = os.path.realpath(ac)
            if real_ac.startswith(doc_dir) and os.path.exists(real_ac):
                try:
                    with open(real_ac, "r", encoding="utf-8", errors="replace") as f:
                        architecture_overview = f.read()
                    break
                except Exception:
                    pass

        # 3. For local / obsidian target: directly run fast LLM synthesis with 15s timeout
        if req.target_type in ["obsidian", "local"] or not url:
            from llm_service import LLMService
            from prompts import get_reconcile_system_prompt, get_reconcile_user_prompt
            from pending_manager import PendingManager
            
            # Fetch and format active context selection (selected commits & PRs)
            git_formatted = ""
            touched_files_content = ""
            active_repo = bitbucket_repo if git_provider == "bitbucket" else (gitlab_repo if git_provider == "gitlab" else github_repo)
            active_token = bitbucket_token if git_provider == "bitbucket" else (gitlab_token if git_provider == "gitlab" else github_token)
            
            if commits and active_repo:
                try:
                    if git_provider == "bitbucket":
                        from bitbucket_service import BitbucketService
                        gh = BitbucketService(token=active_token, repo=active_repo)
                    elif git_provider == "gitlab":
                        from gitlab_service import GitLabService
                        gh = GitLabService(host=gitlab_host, token=active_token, repo=active_repo)
                    else:
                        from github_service import GitHubService
                        gh = GitHubService(token=active_token, repo=active_repo)
                    commits_info = await gh.get_commit_info(commits)
                    touched_paths = []
                    for c in commits_info:
                        if "error" in c: continue
                        git_formatted += f"Commit: {c['hexsha']}\nAuthor: {c['author']}\nMessage: {c['message']}\n"
                        for diff in c.get("diffs", []):
                            diff_text = diff['diff']
                            if len(diff_text) > 4000:
                                diff_text = diff_text[:4000] + "\n...[DIFF TRUNCATED]..."
                            git_formatted += f"File: {diff['a_path']} -> {diff['b_path']}\nDiff:\n{diff_text}\n"
                            p = diff.get("b_path") or diff.get("a_path")
                            if p and p not in touched_paths and p != "commit_diff":
                                touched_paths.append(p)
                                
                    # Fetch full source text of key touched files for deep context
                    for p in touched_paths[:4]:
                        file_text = ""
                        if os.path.exists(p):
                            try:
                                with open(p, "r", encoding="utf-8", errors="replace") as f:
                                    file_text = f.read()
                            except Exception:
                                pass
                        elif active_repo and active_token:
                            try:
                                file_text = await gh.get_file_content(p)
                                if file_text.startswith("Error:"):
                                    file_text = ""
                            except Exception:
                                pass
                        if file_text:
                            if len(file_text) > 6000:
                                file_text = file_text[:6000] + "\n...[FILE TRUNCATED]..."
                            touched_files_content += f"=== Full Source File: {p} ===\n{file_text}\n\n"
                except Exception as e:
                    print(f"[!] Note: Could not fetch remote commit diffs/files: {e}")

            github_formatted = ""
            if prs and active_repo:
                try:
                    if git_provider == "bitbucket":
                        from bitbucket_service import BitbucketService
                        gh = BitbucketService(token=active_token, repo=active_repo)
                    elif git_provider == "gitlab":
                        from gitlab_service import GitLabService
                        gh = GitLabService(host=gitlab_host, token=active_token, repo=active_repo)
                    else:
                        from github_service import GitHubService
                        gh = GitHubService(token=active_token, repo=active_repo)
                    for pr_num in prs:
                        pr_data = await gh.get_pr_details(pr_num)
                        if "error" not in pr_data:
                            github_formatted += f"PR #{pr_data['number']}: {pr_data['title']}\nDescription: {pr_data['description']}\n\n"
                except Exception as e:
                    print(f"[!] Note: Could not fetch PR details: {e}")

            system_prompt = get_reconcile_system_prompt()
            user_prompt = get_reconcile_user_prompt(
                voice_text=combined_thoughts,
                git_formatted=git_formatted,
                github_formatted=github_formatted,
                available_docs=available_docs_str,
                architecture_overview=architecture_overview,
                touched_files_content=touched_files_content,
                specific_target_file=target_path,
                specific_target_content=current_content
            )
            if req.custom_prompt:
                user_prompt += f"\n\nAdditional User Guidance:\n{req.custom_prompt}"
                
            llm = LLMService()
            try:
                updated_content = await asyncio.wait_for(
                    llm.generate(
                        prompt=user_prompt,
                        system_prompt=system_prompt,
                        model=llm_model,
                        api_key=llm_api_key,
                        provider=llm_provider,
                        base_url=req.llm_base_url
                    ),
                    timeout=90.0
                )
            except (asyncio.TimeoutError, Exception) as primary_err:
                if llm_model != "openai/gpt-4o-mini" and llm_provider in ["dicty_cloud", "openrouter"]:
                    print(f"[!] Primary model '{llm_model}' failed or timed out ({primary_err}). Automatically falling back to 'openai/gpt-4o-mini'...")
                    updated_content = await asyncio.wait_for(
                        llm.generate(
                            prompt=user_prompt,
                            system_prompt=system_prompt,
                            model="openai/gpt-4o-mini",
                            api_key=llm_api_key,
                            provider=llm_provider,
                            base_url=req.llm_base_url
                        ),
                        timeout=60.0
                    )
                else:
                    raise primary_err
            
            # 3. Parse Autonomous LLM Decision (JSON or fallback markdown)
            doc_filename = os.path.basename(target_path) if target_path else "DOCUMENTATION.md"
            doc_title = os.path.splitext(doc_filename)[0].replace("_", " ").title()
            doc_action = "update"
            final_markdown = updated_content.strip()

            # Clean JSON if wrapped in markdown fences
            clean_json_str = updated_content.strip()
            if clean_json_str.startswith("```json"):
                clean_json_str = clean_json_str[7:]
            if clean_json_str.startswith("```"):
                clean_json_str = clean_json_str[3:]
            if clean_json_str.endswith("```"):
                clean_json_str = clean_json_str[:-3]
            clean_json_str = clean_json_str.strip()

            try:
                parsed_json = json.loads(clean_json_str)
                if isinstance(parsed_json, dict):
                    if parsed_json.get("target_file"):
                        doc_filename = os.path.basename(parsed_json["target_file"].strip())
                        if not doc_filename.endswith(".md"):
                            doc_filename += ".md"
                    if parsed_json.get("title"):
                        doc_title = parsed_json["title"].strip()
                    if parsed_json.get("action"):
                        doc_action = parsed_json["action"].strip()
                    if parsed_json.get("proposed_content"):
                        final_markdown = parsed_json["proposed_content"].strip()
            except Exception:
                pass

            # Resolve target path strictly within doc_dir
            safe_doc_name = os.path.basename(doc_filename)
            candidate_target = target_path or os.path.realpath(os.path.join(doc_dir, safe_doc_name))
            try:
                if os.path.commonpath([doc_dir, candidate_target]) == doc_dir:
                    final_target_path = candidate_target
                else:
                    final_target_path = os.path.realpath(os.path.join(doc_dir, safe_doc_name))
            except (ValueError, OSError):
                final_target_path = os.path.realpath(os.path.join(doc_dir, safe_doc_name))

            # Read original content if file already existed
            real_original_content = ""
            if os.path.exists(final_target_path):
                try:
                    with open(final_target_path, "r", encoding="utf-8", errors="replace") as f:
                        real_original_content = f.read()
                except Exception:
                    pass
            else:
                doc_action = "create"
                real_original_content = "New File: This file does not exist yet."

            pm = PendingManager()
            pending_id = pm.create_pending_update(
                title=doc_filename,
                original_content=real_original_content,
                proposed_content=final_markdown,
                page_id=final_target_path,
                version=1,
                confluence_url=obsidian_path if req.target_type == "obsidian" else final_target_path,
                space_key="",
                target_type=req.target_type or "local",
                action=doc_action
            )
            
            if req.clear_queue_on_success:
                queue_manager.clear()
                
            set_status("Ready")
            return {
                "status": "success",
                "data": {"status": "success", "pending_ids": [pending_id]},
                "message": f"Documentation proposal created for {doc_filename}. Check Pending Updates!",
                "synthesized_count": len(thought_texts)
            }
        else:
            # For remote targets (Confluence, Linear): call orchestrator with 120s timeout
            async with httpx.AsyncClient(timeout=120.0) as client:
                resp = await client.post(url, json=payload)
                if resp.status_code != 200:
                    error_detail = resp.text
                    try:
                        error_json = resp.json()
                        error_detail = error_json.get("detail", error_detail)
                    except Exception:
                        pass
                    set_status("Ready")
                    return {"status": "error", "message": f"Synthesis error: {error_detail}"}
                result = resp.json()
                if req.clear_queue_on_success:
                    queue_manager.clear()
                set_status("Ready")
                return {
                    "status": "success",
                    "data": result,
                    "message": result.get("message", "Documentation synthesized! Check Pending Updates."),
                    "synthesized_count": len(thought_texts)
                }
    except asyncio.TimeoutError:
        set_status("Ready")
        print("[!] Synthesis timed out after 120s")
        return {"status": "error", "message": "Synthesis timed out after 120 seconds. Please check your LLM provider configuration."}
    except Exception as e:
        set_status("Ready")
        import traceback
        traceback.print_exc()
        print(f"[!] Synthesis failed: {e}")
        return {"status": "error", "message": "Synthesis failed due to an internal error."}
