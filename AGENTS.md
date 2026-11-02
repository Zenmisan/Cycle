# Project Rules: Cycle

## Process Enforcement: Ralph's Method
Always follow Ralph's Method for all software tasks in this repository:
1. Always maintain `.agents/tracks.md` as the master index of tracks.
2. For each task or feature, create a track directory: `.agents/tracks/<track_name>_<YYYYMMDD>/`.
3. In that directory, always maintain:
   - `spec.md`: User problem statement, technical requirements, acceptance criteria.
   - `plan.md`: Step-by-step implementation tasks, dependencies, and explicit verification commands.
4. Register the new track under `## Active` in `.agents/tracks.md`.
5. Execute the plan step-by-step with rigorous verification (TDD / automated tests).
6. Move the track to `## Completed` in `.agents/tracks.md` when fully verified.
