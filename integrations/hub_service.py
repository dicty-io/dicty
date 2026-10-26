import os
from llm_service import LLMService

class HubService:
    def __init__(self, hub_path: str = "README.md"):
        self.hub_path = hub_path
        self.llm_service = LLMService()

    async def sync_spoke_to_hub(self, spoke_path: str, spoke_content: str) -> bool:
        # 1. Read existing Hub content
        current_hub_content = ""
        if os.path.exists(self.hub_path):
            try:
                with open(self.hub_path, "r") as f:
                    current_hub_content = f.read()
            except Exception as e:
                print(f"Error reading Hub file: {e}")
                return False

        from prompts import get_hub_system_prompt, get_hub_user_prompt
        system_prompt = get_hub_system_prompt()
        user_prompt = get_hub_user_prompt(self.hub_path, current_hub_content, spoke_path, spoke_content)

        try:
            updated_hub = await self.llm_service.generate(prompt=user_prompt, system_prompt=system_prompt)
            
            # Ensure parent directories exist
            os.makedirs(os.path.dirname(os.path.abspath(self.hub_path)), exist_ok=True)
            with open(self.hub_path, "w") as f:
                f.write(updated_hub)
            return True
        except Exception as e:
            print(f"Error generating Hub update: {e}")
            return False
