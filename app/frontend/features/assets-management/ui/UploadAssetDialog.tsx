import { zodResolver } from '@hookform/resolvers/zod';
import CloudUploadIcon from '@mui/icons-material/CloudUpload';
import DeleteIcon from '@mui/icons-material/Delete';
import InsertDriveFileIcon from '@mui/icons-material/InsertDriveFile';
import {
  Box,
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  LinearProgress,
  Stack,
  TextField,
  Typography,
} from '@mui/material';
import AwsS3 from '@uppy/aws-s3';
import Uppy from '@uppy/core';
import type { Body, Meta, UppyFile } from '@uppy/core';
import { useSnackbar } from 'notistack';
import { type FC, useCallback, useEffect, useRef, useState } from 'react';
import { useForm } from 'react-hook-form';

import { setErrorsToForm } from 'shared/api';

import { useCreateCompanyAssetMutation, useCreateProjectAssetMutation } from '../api/assetsApi';
import { uploadAssetSchema, type UploadAssetFormData } from '../lib/assetSchema';
import type { CachedFileData } from '../lib/types';

const PRESIGN_URL = '/api/v1/assets/presign';
const MAX_FILE_SIZE = 1024 * 1024 * 1024; // 1 GB

interface UploadAssetDialogProps {
  open: boolean;
  onClose: () => void;
  projectId?: number;
}

function extractCachedFileData(uploadURL: string): CachedFileData {
  const url = new URL(uploadURL, window.location.origin);
  const pathname = decodeURIComponent(url.pathname);
  const cachePrefix = '/cache/';
  const idx = pathname.indexOf(cachePrefix);
  if (idx === -1) throw new Error('Cannot extract cache data from upload URL');
  return { id: pathname.substring(idx + cachePrefix.length), storage: 'cache' };
}

function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

const UploadAssetDialog: FC<UploadAssetDialogProps> = ({ open, onClose, projectId }) => {
  const { enqueueSnackbar } = useSnackbar();

  const [createCompanyAsset, { isLoading: isCreatingCompany }] = useCreateCompanyAssetMutation();
  const [createProjectAsset, { isLoading: isCreatingProject }] = useCreateProjectAssetMutation();
  const isSaving = isCreatingCompany || isCreatingProject;

  const [uploadProgress, setUploadProgress] = useState(0);
  const [isUploading, setIsUploading] = useState(false);
  const [uppyFiles, setUppyFiles] = useState<UppyFile<Meta, Body>[]>([]);

  const uppyRef = useRef<InstanceType<typeof Uppy<Meta, Body>> | null>(null);
  if (!uppyRef.current) {
    uppyRef.current = new Uppy<Meta, Body>({
      restrictions: { maxFileSize: MAX_FILE_SIZE, maxNumberOfFiles: 1 },
      autoProceed: false,
    }).use(AwsS3, {
      shouldUseMultipart: false,
      getUploadParameters: async (file) => {
        const qs = new URLSearchParams({
          filename: file.name ?? 'file',
          type: file.type ?? 'application/octet-stream',
        });
        const res = await fetch(`${PRESIGN_URL}?${qs}`, { credentials: 'same-origin' });
        if (!res.ok) throw new Error('Failed to get upload parameters');
        return await res.json();
      },
    });
  }
  const uppy = uppyRef.current!;

  const methods = useForm<UploadAssetFormData>({
    resolver: zodResolver(uploadAssetSchema),
    defaultValues: { name: '', folder: '' },
  });

  useEffect(() => {
    const onFileAdded = () => setUppyFiles(uppy.getFiles());
    const onFileRemoved = () => setUppyFiles(uppy.getFiles());
    const onProgress = (
      _file: UppyFile<Meta, Body> | undefined,
      progress: { bytesUploaded: number; bytesTotal: number | null },
    ) => {
      if (progress?.bytesTotal && progress.bytesTotal > 0) {
        setUploadProgress(Math.round((progress.bytesUploaded / progress.bytesTotal) * 100));
      }
    };

    uppy.on('file-added', onFileAdded);
    uppy.on('file-removed', onFileRemoved);
    uppy.on('upload-progress', onProgress);

    return () => {
      uppy.off('file-added', onFileAdded);
      uppy.off('file-removed', onFileRemoved);
      uppy.off('upload-progress', onProgress);
    };
  }, [uppy]);

  useEffect(() => {
    if (open) {
      methods.reset({ name: '', folder: '' });
      uppy.cancelAll();
      setUppyFiles([]);
      setUploadProgress(0);
      setIsUploading(false);
    }
  }, [open, methods, uppy]);

  const handleFileSelect = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (!file) return;

      uppy.cancelAll();
      try {
        uppy.addFile({ name: file.name, type: file.type, data: file, source: 'local' });
      } catch (err) {
        enqueueSnackbar(err instanceof Error ? err.message : 'Failed to add file', { variant: 'error' });
        return;
      }

      if (!methods.getValues('name')) {
        methods.setValue('name', file.name);
      }

      e.target.value = '';
    },
    [uppy, methods, enqueueSnackbar],
  );

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault();
      const file = e.dataTransfer.files[0];
      if (!file) return;

      uppy.cancelAll();
      try {
        uppy.addFile({ name: file.name, type: file.type, data: file, source: 'local' });
      } catch (err) {
        enqueueSnackbar(err instanceof Error ? err.message : 'Failed to add file', { variant: 'error' });
        return;
      }

      if (!methods.getValues('name')) {
        methods.setValue('name', file.name);
      }
    },
    [uppy, methods, enqueueSnackbar],
  );

  const handleClose = () => {
    uppy.cancelAll();
    methods.reset();
    onClose();
  };

  const onSubmit = async (data: UploadAssetFormData) => {
    const files = uppy.getFiles();
    if (files.length === 0) {
      enqueueSnackbar('Please select a file', { variant: 'warning' });
      return;
    }

    try {
      setIsUploading(true);
      setUploadProgress(0);

      const result = await uppy.upload();
      if (!result?.successful?.length) {
        const errorMsg = result?.failed?.[0]?.error ?? 'Upload failed';
        throw new Error(errorMsg);
      }

      const uploaded = result.successful[0];
      const cachedFile = extractCachedFileData(uploaded.uploadURL ?? '');

      const payload = {
        name: data.name,
        folder: data.folder || undefined,
        file: cachedFile,
      };

      if (projectId) {
        await createProjectAsset({ projectId, ...payload }).unwrap();
      } else {
        await createCompanyAsset(payload).unwrap();
      }

      enqueueSnackbar('Asset uploaded successfully', { variant: 'success' });
      handleClose();
    } catch (error: unknown) {
      const message = setErrorsToForm(error, methods.setError) || 'Failed to upload asset';
      enqueueSnackbar(message, { variant: 'error' });
    } finally {
      setIsUploading(false);
    }
  };

  const isLoading = isUploading || isSaving;
  const currentFile = uppyFiles[0];

  return (
    <Dialog open={open} onClose={handleClose} maxWidth="sm" fullWidth>
      <DialogTitle>Upload Asset</DialogTitle>
      <form onSubmit={methods.handleSubmit(onSubmit)}>
        <DialogContent>
          <Stack spacing={3}>
            {currentFile ? (
              <Box
                sx={{
                  border: '1px solid',
                  borderColor: 'success.main',
                  borderRadius: 1,
                  p: 2,
                  display: 'flex',
                  alignItems: 'center',
                  gap: 1.5,
                }}
              >
                <InsertDriveFileIcon sx={{ color: 'success.main' }} />
                <Box sx={{ flex: 1, minWidth: 0 }}>
                  <Typography noWrap sx={{ fontSize: 14 }}>
                    {currentFile.name}
                  </Typography>
                  <Typography sx={{ color: 'text.disabled', fontSize: 12 }}>
                    {formatFileSize(currentFile.size ?? 0)}
                  </Typography>
                </Box>
                <Button
                  size="small"
                  color="error"
                  onClick={() => uppy.cancelAll()}
                  disabled={isLoading}
                  sx={{ minWidth: 'auto' }}
                >
                  <DeleteIcon fontSize="small" />
                </Button>
              </Box>
            ) : (
              <Box
                onDrop={handleDrop}
                onDragOver={(e) => e.preventDefault()}
                sx={{
                  border: '2px dashed',
                  borderColor: 'border.defaultAlt',
                  borderRadius: 1,
                  p: 3,
                  textAlign: 'center',
                  cursor: 'pointer',
                  transition: 'border-color 0.2s',
                  '&:hover': { borderColor: 'primary.main' },
                }}
                component="label"
              >
                <CloudUploadIcon sx={{ fontSize: 40, color: 'text.secondaryAlt', mb: 1 }} />
                <Typography sx={{ color: 'text.secondaryAlt', fontSize: 14 }}>
                  Drag & drop or click to select a file
                </Typography>
                <Typography sx={{ color: 'text.disabled', fontSize: 12, mt: 0.5 }}>Max file size: 1 GB</Typography>
                <input type="file" hidden onChange={handleFileSelect} />
              </Box>
            )}

            {isUploading && (
              <Box>
                <LinearProgress variant="determinate" value={uploadProgress} sx={{ borderRadius: 1 }} />
                <Typography sx={{ color: 'text.secondary', fontSize: 12, mt: 0.5, textAlign: 'center' }}>
                  Uploading... {uploadProgress}%
                </Typography>
              </Box>
            )}

            <TextField
              {...methods.register('name')}
              label="Name"
              fullWidth
              error={!!methods.formState.errors.name}
              helperText={methods.formState.errors.name?.message || 'File identifier (auto-populated from filename)'}
            />

            <TextField
              {...methods.register('folder')}
              label="Folder"
              placeholder="e.g. reports, images"
              fullWidth
              error={!!methods.formState.errors.folder}
              helperText={
                methods.formState.errors.folder?.message || 'Optional folder (lowercase, hyphens, underscores)'
              }
            />
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={handleClose} disabled={isLoading}>
            Cancel
          </Button>
          <Button type="submit" variant="contained" disabled={isLoading || !currentFile}>
            {isLoading ? 'Uploading...' : 'Upload'}
          </Button>
        </DialogActions>
      </form>
    </Dialog>
  );
};

export { UploadAssetDialog };
