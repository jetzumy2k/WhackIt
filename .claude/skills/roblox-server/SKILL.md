# Roblox Server Skill
The server is the source of truth.
Validate every remote for player, payload type/size, allowed action, game state, cooldown/rate limit, ownership, numeric ranges, and context.
Never trust client-provided damage, rewards, currency, HP, win state, or purchase completion.
Keep authoritative rules in server Services, not UI/client scripts.
