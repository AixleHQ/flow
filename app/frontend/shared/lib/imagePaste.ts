/** What an agent CLI can attach; the container's upload server takes nothing else. */
const PASTABLE_TYPES = new Set(['image/png', 'image/jpeg', 'image/gif', 'image/webp']);

export function pastedImages(data: DataTransfer | null): File[] {
  if (!data) return [];
  return Array.from(data.files).filter((file) => PASTABLE_TYPES.has(file.type));
}

/** Stores the image in the session's container and returns where it landed there. */
export async function uploadImage(url: string, image: File): Promise<string> {
  const response = await fetch(url, {
    method: 'POST',
    body: image,
    headers: { 'Content-Type': image.type },
    credentials: 'include',
  });
  const body = (await response.json().catch(() => ({}))) as { path?: string; error?: string };
  if (!response.ok || !body.path) {
    throw new Error(body.error ?? 'The image could not be uploaded to this session');
  }
  return body.path;
}
