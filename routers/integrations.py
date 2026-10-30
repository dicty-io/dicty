from fastapi import APIRouter
import httpx
import os
from fastapi import HTTPException, Header, Request
from services.paths import ORCHESTRATOR_URL
from services.stores import local_pending_manager

router = APIRouter()


@router.get("/linear/workspaces")
async def get_linear_workspaces(linear_api_token: str = "", x_linear_token: str = Header(default="")):
    token = x_linear_token.strip() or linear_api_token.strip()
    try:
        async with httpx.AsyncClient() as client:
            # Keep the token out of the URL; the orchestrator accepts X-Linear-Token.
            resp = await client.get(f"{ORCHESTRATOR_URL}/linear/workspaces", headers={"X-Linear-Token": token})
            return resp.json()
    except Exception as e:
        print(f"[!] Failed to fetch linear workspaces: {e}")
        return {"status": "error", "message": "Failed to fetch Linear workspaces", "workspaces": {"teams": [], "projects": []}}


@router.get("/pending_updates")
async def get_pending_updates():
    local_updates = local_pending_manager.get_all()
    try:
        async with httpx.AsyncClient(timeout=0.2) as client:
            resp = await client.get(f"{ORCHESTRATOR_URL}/pending_updates")
            if resp.status_code == 200:
                data = resp.json()
                cloud_updates = data.get("updates") or []
                seen = {u.get("id") for u in local_updates if "id" in u}
                merged = list(local_updates)
                for u in cloud_updates:
                    if u.get("id") not in seen:
                        merged.append(u)
                        seen.add(u.get("id"))
                return {"status": "success", "updates": merged}
    except Exception:
        pass
    return {"status": "success", "updates": local_updates}

@router.get("/updates/history")
async def get_updates_history():
    local_updates = local_pending_manager.get_history()
    try:
        async with httpx.AsyncClient(timeout=0.2) as client:
            resp = await client.get(f"{ORCHESTRATOR_URL}/updates/history")
            if resp.status_code == 200:
                data = resp.json()
                cloud_updates = data.get("updates") or data.get("history") or []
                seen = {u.get("id") for u in local_updates if "id" in u}
                merged = list(local_updates)
                for u in cloud_updates:
                    if u.get("id") not in seen:
                        merged.append(u)
                        seen.add(u.get("id"))
                return {"status": "success", "updates": merged}
    except Exception:
        pass
    return {"status": "success", "updates": local_updates}

@router.delete("/updates/history/{history_id}")
async def delete_update_history_item(history_id: str):
    deleted = local_pending_manager.delete_history_item(history_id)
    return {"status": "success", "deleted": deleted}

@router.delete("/updates/history")
async def clear_updates_history():
    cleared = local_pending_manager.clear_history()
    return {"status": "success", "cleared": cleared}

@router.post("/pending_updates/{pending_id}/approve")
async def approve_pending_update(pending_id: str, req: Request):
    try:
        data = await req.json()
    except Exception:
        data = {}
        
    item = local_pending_manager.get_by_id(pending_id)
    if item:
        from agent_service import clean_markdown_documentation
        target_type = item.get("target_type")
        content = clean_markdown_documentation(item.get("proposed_content", ""))
        title = item.get("title", "ARCHITECTURE.md")
        
        if target_type == "notion":
            from notion_service import NotionService
            notion_api_key = data.get("notion_api_key") or os.getenv("NOTION_API_KEY", "")
            parent_page_id = item.get("confluence_url") or data.get("notion_page_id") or os.getenv("NOTION_PAGE_ID", "")
            print(f"[*] Approving Notion pending update: '{title}' -> parent_page_id: '{parent_page_id}'", flush=True)
            service = NotionService(api_key=notion_api_key, parent_page_id=parent_page_id)
            res = await service.upsert_page(title, content, page_id=item.get("page_id"))
            print(f"[+] Notion upload result: {res}", flush=True)
            if res.get("status") == "failed":
                raise HTTPException(status_code=400, detail=res.get("error", "Failed to upload to Notion"))
                
        elif target_type == "linear":
            from linear_service import LinearService
            lin_api_token = data.get("linear_api_token") or os.getenv("LINEAR_API_KEY", "")
            if not lin_api_token:
                raise HTTPException(status_code=400, detail="Linear API token is required for approval.")
            lin_service = LinearService(lin_api_token)
            if item.get("page_id"):
                lin_service.update_document(item["page_id"], content)
            else:
                workspace_id = item.get("confluence_url", "")
                team_id = workspace_id.replace("team:", "") if workspace_id.startswith("team:") else None
                project_id = workspace_id.replace("project:", "") if workspace_id.startswith("project:") else None
                lin_service.create_document(title, content, project_id=project_id, team_id=team_id)
                
        elif target_type in ["obsidian", "local"]:
            destination = item.get("confluence_url") or item.get("page_id") or os.getcwd()
            try:
                if os.path.isdir(destination) or not destination.lower().endswith(".md"):
                    from obsidian_service import ObsidianService
                    ob_service = ObsidianService(destination)
                    res = ob_service.create_page(title, content)
                    print(f"[+] Approved update published via ObsidianService: {res.get('file', destination)}")
                else:
                    parent_dir = os.path.dirname(os.path.abspath(destination))
                    if parent_dir:
                        os.makedirs(parent_dir, exist_ok=True)
                    with open(destination, "w", encoding="utf-8") as f:
                        f.write(content)
                    print(f"[+] Approved update published to: {destination}")
            except Exception as write_err:
                print(f"[!] Error writing approved content to {destination}: {write_err}")
                raise HTTPException(status_code=500, detail=f"Failed to publish file on approval: {write_err}")
                    
        elif target_type == "confluence":
            from confluence_service import ConfluenceService
            conf_service = ConfluenceService(
                item.get("confluence_url", ""),
                item.get("space_key", ""),
                data.get("username"),
                data.get("api_token")
            )
            if item.get("page_id"):
                await conf_service.update_page(item["page_id"], title, content, item.get("version", 1))
            else:
                await conf_service.create_page(title, content)
                
        local_pending_manager.move_to_history(pending_id, "approved")
        return {"status": "success", "message": f"Update approved and synced to {target_type}"}
        
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(f"{ORCHESTRATOR_URL}/pending_updates/{pending_id}/approve", json=data)
            return resp.json()
    except Exception as e:
        print(f"[!] Pending update approval failed: {e}")
        return {"status": "error", "message": "Failed to approve pending update"}

@router.post("/pending_updates/{pending_id}/reject")
async def reject_pending_update(pending_id: str):
    item = local_pending_manager.get_by_id(pending_id)
    if item:
        local_pending_manager.move_to_history(pending_id, "rejected")
        return {"status": "success", "message": "Update rejected"}
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(f"{ORCHESTRATOR_URL}/pending_updates/{pending_id}/reject")
            return resp.json()
    except Exception as e:
        print(f"[!] Pending update rejection failed: {e}")
        return {"status": "error", "message": "Failed to reject pending update"}

@router.delete("/pending_updates/{pending_id}")
async def delete_pending_update(pending_id: str):
    return await reject_pending_update(pending_id)

@router.post("/updates/history/{history_id}/reupload")
async def proxy_reupload_history_update(history_id: str, req: Request):
    try:
        data = await req.json()
    except Exception:
        data = {}
        
    item = local_pending_manager.get_history_by_id(history_id)
    if item:
        target_type = item.get("target_type")
        content = item.get("proposed_content", "")
        title = item.get("title", "ARCHITECTURE.md")
        
        if target_type == "notion":
            from notion_service import NotionService
            notion_api_key = data.get("notion_api_key") or os.getenv("NOTION_API_KEY", "")
            parent_page_id = item.get("confluence_url") or data.get("notion_page_id") or os.getenv("NOTION_PAGE_ID", "")
            print(f"[*] Re-uploading Notion update: '{title}' -> parent_page_id: '{parent_page_id}'", flush=True)
            service = NotionService(api_key=notion_api_key, parent_page_id=parent_page_id)
            res = await service.upsert_page(title, content, page_id=item.get("page_id"))
            if res.get("status") == "failed":
                raise HTTPException(status_code=400, detail=res.get("error", "Failed to upload to Notion"))
                
        elif target_type == "linear":
            from linear_service import LinearService
            lin_api_token = data.get("linear_api_token") or os.getenv("LINEAR_API_KEY", "")
            if not lin_api_token:
                raise HTTPException(status_code=400, detail="Linear API token is required for re-upload.")
            lin_service = LinearService(lin_api_token)
            if item.get("page_id"):
                lin_service.update_document(item["page_id"], content)
            else:
                workspace_id = item.get("confluence_url", "")
                team_id = workspace_id.replace("team:", "") if workspace_id.startswith("team:") else None
                project_id = workspace_id.replace("project:", "") if workspace_id.startswith("project:") else None
                lin_service.create_document(title, content, project_id=project_id, team_id=team_id)
                
        elif target_type in ["obsidian", "local"]:
            target_path = item.get("page_id") or item.get("confluence_url")
            if not target_path:
                raise HTTPException(status_code=400, detail="No destination file path specified for local/obsidian update.")
            try:
                parent_dir = os.path.dirname(os.path.abspath(target_path))
                if parent_dir:
                    os.makedirs(parent_dir, exist_ok=True)
                with open(target_path, "w", encoding="utf-8") as f:
                    f.write(content)
            except Exception as write_err:
                print(f"[!] Error writing re-uploaded content to {target_path}: {write_err}")
                raise HTTPException(status_code=500, detail=f"Failed to write re-uploaded file: {write_err}") from write_err
                    
        elif target_type == "confluence":
            from confluence_service import ConfluenceService
            conf_service = ConfluenceService(
                item.get("confluence_url", ""),
                item.get("space_key", ""),
                data.get("username"),
                data.get("api_token")
            )
            if item.get("page_id"):
                await conf_service.update_page(item["page_id"], title, content, item.get("version", 1))
            else:
                await conf_service.create_page(title, content)
                
        return {"status": "success", "message": f"Successfully re-uploaded '{title}' to {target_type}!"}
        
    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            resp = await client.post(f"{ORCHESTRATOR_URL}/updates/history/{history_id}/reupload", json=data)
            return resp.json()
    except Exception as e:
        print(f"[!] Re-upload proxy failed: {e}")
        return {"status": "error", "message": "Failed to re-upload update"}

@router.post("/notion/test_connection")
async def test_notion_connection(req: Request):
    try:
        data = await req.json()
    except Exception:
        data = {}
    from notion_service import NotionService
    api_key = data.get("api_key", "")
    parent_page_id = data.get("parent_page_id", "")
    service = NotionService(api_key=api_key, parent_page_id=parent_page_id)
    return await service.test_connection()

@router.post("/reconcile/notion")
async def proxy_reconcile_notion(req: Request):
    try:
        data = await req.json()
    except Exception:
        data = {}
    try:
        async with httpx.AsyncClient(timeout=300.0) as client:
            resp = await client.post(f"{ORCHESTRATOR_URL}/reconcile/notion", json=data)
            if resp.status_code != 200:
                print(f"[ERROR] Proxy /reconcile/notion failed: {resp.status_code} - {resp.text}", flush=True)
            return resp.json()
    except Exception as e:
        print(f"[!] Reconcile Notion proxy failed: {e}")
        return {"status": "error", "message": "Failed to reconcile with Notion"}

@router.post("/reconcile/architecture")
async def proxy_reconcile_architecture(req: Request):
    try:
        data = await req.json()
    except Exception:
        data = {}
    try:
        async with httpx.AsyncClient(timeout=300.0) as client:
            resp = await client.post(f"{ORCHESTRATOR_URL}/reconcile/architecture", json=data)
            if resp.status_code != 200:
                print(f"[ERROR] Proxy /reconcile/architecture failed: {resp.status_code} - {resp.text}", flush=True)
                try:
                    err_json = resp.json()
                    detail = err_json.get("detail") or err_json.get("message") or resp.text
                except Exception:
                    detail = resp.text
                raise HTTPException(status_code=resp.status_code, detail=f"{detail}")
            return resp.json()
    except httpx.ReadTimeout:
        raise HTTPException(status_code=504, detail="Documentation generation timed out while waiting for the LLM response. Please retry with a faster model.")
    except HTTPException:
        raise
    except Exception as e:
        print(f"[*] Standalone orchestrator ({ORCHESTRATOR_URL}) not available ({e}). Executing architecture generation locally in-process...", flush=True)
        try:
            from main import reconcile_architecture, ArchitectureReconcileRequest
            arch_req = ArchitectureReconcileRequest(**data)
            return await reconcile_architecture(arch_req)
        except HTTPException:
            raise
        except Exception as local_err:
            err_msg = str(local_err) or local_err.__class__.__name__
            print(f"[ERROR] Local reconcile_architecture failed: {err_msg}", flush=True)
            raise HTTPException(status_code=500, detail=f"Architecture generation failed: {err_msg}")
