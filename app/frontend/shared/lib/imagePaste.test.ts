import { describe, expect, it } from 'vitest';

import { answerFetch, jsonResponse } from 'test/fetchStub';

import { pastedImages, uploadImage } from './imagePaste';

const UPLOAD_URL = 'http://sandbox.test/t/abc123/upload';

function transfer(...files: File[]): DataTransfer {
  return { files } as unknown as DataTransfer;
}

describe('pastedImages', () => {
  it('keeps the images an agent CLI can attach', () => {
    const png = new File(['x'], 'shot.png', { type: 'image/png' });
    const svg = new File(['x'], 'logo.svg', { type: 'image/svg+xml' });
    const text = new File(['x'], 'notes.txt', { type: 'text/plain' });

    expect(pastedImages(transfer(png, svg, text))).toEqual([png]);
    expect(pastedImages(null)).toEqual([]);
  });
});

describe('uploadImage', () => {
  it('returns the path the container stored the image at', async () => {
    const fetchSpy = answerFetch({ [`POST ${UPLOAD_URL}`]: jsonResponse({ path: '/tmp/aixle-uploads/a.png' }, 201) });

    const path = await uploadImage(UPLOAD_URL, new File(['x'], 'a.png', { type: 'image/png' }));

    expect(path).toBe('/tmp/aixle-uploads/a.png');
    expect(fetchSpy.mock.calls[0][1]).toMatchObject({
      credentials: 'include',
      headers: { 'Content-Type': 'image/png' },
    });
  });

  it("surfaces the container's refusal", async () => {
    answerFetch({ [`POST ${UPLOAD_URL}`]: jsonResponse({ error: 'Images are limited to 10.0 MB' }, 413) });

    await expect(uploadImage(UPLOAD_URL, new File(['x'], 'a.png', { type: 'image/png' }))).rejects.toThrow(
      'Images are limited to 10.0 MB',
    );
  });

  it('explains a session whose container predates image paste', async () => {
    answerFetch({ [`POST ${UPLOAD_URL}`]: new Response('404 page not found', { status: 404 }) });

    await expect(uploadImage(UPLOAD_URL, new File(['x'], 'a.png', { type: 'image/png' }))).rejects.toThrow(
      'The image could not be uploaded to this session',
    );
  });
});
