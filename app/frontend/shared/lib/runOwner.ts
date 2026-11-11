/** Who a run belongs to, naming the team it was picked from: "Planner → Anna". */
export function runOwnerLabel(teamName: string | null | undefined, userName: string | null | undefined): string | null {
  if (!userName) return teamName ?? null;
  return teamName ? `${teamName} → ${userName}` : userName;
}
