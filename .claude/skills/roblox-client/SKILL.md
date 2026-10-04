# Roblox Client Skill
The client owns input, UI, camera, animation, sound, particles, and visual feedback only.
Never let the client authoritatively decide damage, HP, currency, rewards, unlocks, purchases, or progression.
Flow: Input -> client sanity check -> Remote request -> server validation -> server result -> presentation.
Avoid unnecessary Heartbeat loops, RemoteEvent spam, instance churn, and leaked connections.
