import { zodResolver } from '@hookform/resolvers/zod';
import CloudUploadIcon from '@mui/icons-material/CloudUpload';
import DeleteIcon from '@mui/icons-material/Delete';
import InsertDriveFileIcon from '@mui/icons-material/InsertDriveFile';
import {
  Autocomplete,
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
import { Controller, useForm } from 'react-hook-form';

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
  folders?: string[];
}

function extractCachedFileData(uploadURL: string): CachedFileData {
  const url = new URL(uploadURL, window.location.origin);
  const pathname = decodeURIComponent(url.pathname.replace(/\+/g, '%20'));
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

const UploadAssetDialog: FC<UploadAssetDialogProps> = ({ open, onClose, projectId, folders = [] }) => {
  const { enqueueSnackbar } = useSnackbar();

  const [createCompanyAsset, { isLoading: isCreatingCompany }] = useCreateCompanyAssetMutation();
  const [createProjectAsset, { isLoading: isCreatingProject }] = useCreateProjectAssetMutation();
  const isSaving = isCreatingCompany || isCreatingProject;

  const [uploadProgress, setUploadProgress] = useState(0);
  const [isUploading, setIsUploading] = useState(false);
  const [uppyFiles, setUppyFiles] = useState<UppyFile<Meta, Body>[]>([]);
  const [isDragOver, setIsDragOver] = useState(false);

  const uppyRef = useRef<InstanceType<typeof Uppy<Meta, Body>> | null>(null);
  if (!uppyRef.current) {
    uppyRef.current = new Uppy<Meta, Body>({
      restrictions: { maxFileSize: MAX_FILE_SIZE },
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
    defaultValues: { folder: '' },
  });

  useEffect(() => {
    const syncFiles = () => setUppyFiles(uppy.getFiles());
    const onProgress = (
      _file: UppyFile<Meta, Body> | undefined,
      progress: { bytesUploaded: number; bytesTotal: number | null },
    ) => {
      if (progress?.bytesTotal && progress.bytesTotal > 0) {
        setUploadProgress(Math.round((progress.bytesUploaded / progress.bytesTotal) * 100));
      }
    };

    uppy.on('file-added', syncFiles);
    uppy.on('file-removed', syncFiles);
    uppy.on('upload-progress', onProgress);

    return () => {
      uppy.off('file-added', syncFiles);
      uppy.off('file-removed', syncFiles);
      uppy.off('upload-progress', onProgress);
    };
  }, [uppy]);

  useEffect(() => {
    if (open) {
      methods.reset({ folder: '' });
      uppy.cancelAll();
      setUppyFiles([]);
      setUploadProgress(0);
      setIsUploading(false);
    }
  }, [open, methods, uppy]);

  const addFiles = useCallback(
    (fileList: FileList) => {
      Array.from(fileList).forEach((file) => {
        try {
          uppy.addFile({ name: file.name, type: file.type, data: file, source: 'local' });
        } catch (err) {
          enqueueSnackbar(err instanceof Error ? err.message : 'Failed to add file', { variant: 'error' });
        }
      });
    },
    [uppy, enqueueSnackbar],
  );

  const handleFileSelect = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      if (e.target.files) addFiles(e.target.files);
      e.target.value = '';
    },
    [addFiles],
  );

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault();
      setIsDragOver(false);
      if (e.dataTransfer.files.length) addFiles(e.dataTransfer.files);
    },
    [addFiles],
  );

  const handleRemoveFile = useCallback(
    (fileId: string) => {
      uppy.removeFile(fileId);
    },
    [uppy],
  );

  const handleClose = () => {
    uppy.cancelAll();
    methods.reset();
    onClose();
  };

  const onSubmit = async (data: UploadAssetFormData) => {
    const files = uppy.getFiles();
    if (files.length === 0) {
      enqueueSnackbar('Please select at least one file', { variant: 'warning' });
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

      const folder = data.folder || undefined;
      let failed = 0;

      for (const uploaded of result.successful) {
        const cachedFile = extractCachedFileData(uploaded.uploadURL ?? '');
        const payload = {
          name: uploaded.name ?? 'file',
          folder,
          file: cachedFile,
        };

        try {
          if (projectId) {
            await createProjectAsset({ projectId, ...payload }).unwrap();
          } else {
            await createCompanyAsset(payload).unwrap();
          }
        } catch (error: unknown) {
          failed++;
          const message = setErrorsToForm(error, methods.setError) || `Failed to create asset "${uploaded.name}"`;
          enqueueSnackbar(message, { variant: 'error' });
        }
      }

      const succeeded = result.successful.length - failed;
      if (succeeded > 0) {
        enqueueSnackbar(succeeded === 1 ? 'Asset uploaded successfully' : `${succeeded} assets uploaded successfully`, {
          variant: 'success',
        });
      }

      if (failed === 0) handleClose();
    } catch (error: unknown) {
      const message = setErrorsToForm(error, methods.setError) || 'Failed to upload assets';
      enqueueSnackbar(message, { variant: 'error' });
    } finally {
      setIsUploading(false);
    }
  };

  const isLoading = isUploading || isSaving;

  return (
    <Dialog open={open} onClose={handleClose} maxWidth="sm" fullWidth>
      <DialogTitle>Upload Assets</DialogTitle>
      <form onSubmit={methods.handleSubmit(onSubmit)}>
        <DialogContent>
          <Stack spacing={3}>
            <Box
              onDrop={handleDrop}
              onDragOver={(e) => {
                e.preventDefault();
                setIsDragOver(true);
              }}
              onDragLeave={() => setIsDragOver(false)}
              sx={{
                border: '2px dashed',
                borderColor: isDragOver ? 'primary.main' : 'border.defaultAlt',
                backgroundColor: isDragOver ? 'action.hover' : 'transparent',
                borderRadius: 1,
                p: 3,
                textAlign: 'center',
                cursor: 'pointer',
                transition: 'border-color 0.2s, background-color 0.2s',
                '&:hover': { borderColor: 'primary.main' },
              }}
              component="label"
            >
              <CloudUploadIcon sx={{ fontSize: 40, color: 'text.secondaryAlt', mb: 1 }} />
              <Typography sx={{ color: 'text.secondaryAlt', fontSize: 14 }}>
                Drag & drop or click to select files
              </Typography>
              <Typography sx={{ color: 'text.disabled', fontSize: 12, mt: 0.5 }}>Max file size: 1 GB</Typography>
              <input type="file" hidden multiple onChange={handleFileSelect} />
            </Box>

            {uppyFiles.length > 0 && (
              <Stack spacing={1}>
                {uppyFiles.map((file) => (
                  <Box
                    key={file.id}
                    sx={{
                      border: '1px solid',
                      borderColor: 'success.main',
                      borderRadius: 1,
                      px: 2,
                      py: 1,
                      display: 'flex',
                      alignItems: 'center',
                      gap: 1.5,
                    }}
                  >
                    <InsertDriveFileIcon sx={{ color: 'success.main', fontSize: 20 }} />
                    <Box sx={{ flex: 1, minWidth: 0 }}>
                      <Typography noWrap sx={{ fontSize: 14 }}>
                        {file.name}
                      </Typography>
                      <Typography sx={{ color: 'text.disabled', fontSize: 12 }}>
                        {formatFileSize(file.size ?? 0)}
                      </Typography>
                    </Box>
                    <Button
                      size="small"
                      color="error"
                      onClick={() => handleRemoveFile(file.id)}
                      disabled={isLoading}
                      sx={{ minWidth: 'auto', p: 0.5 }}
                    >
                      <DeleteIcon fontSize="small" />
                    </Button>
                  </Box>
                ))}
              </Stack>
            )}

            {isUploading && (
              <Box>
                <LinearProgress variant="determinate" value={uploadProgress} sx={{ borderRadius: 1 }} />
                <Typography sx={{ color: 'text.secondary', fontSize: 12, mt: 0.5, textAlign: 'center' }}>
                  Uploading... {uploadProgress}%
                </Typography>
              </Box>
            )}

            <Controller
              name="folder"
              control={methods.control}
              render={({ field, fieldState }) => (
                <Autocomplete
                  freeSolo
                  options={folders}
                  value={field.value || ''}
                  onChange={(_e, newValue) => field.onChange(newValue ?? '')}
                  onInputChange={(_e, newValue) => field.onChange(newValue ?? '')}
                  renderInput={(params) => (
                    <TextField
                      {...params}
                      label="Folder"
                      placeholder="Select or type a folder name"
                      error={!!fieldState.error}
                      helperText={fieldState.error?.message || 'Optional folder (lowercase, hyphens, underscores)'}
                    />
                  )}
                />
              )}
            />
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={handleClose} disabled={isLoading}>
            Cancel
          </Button>
          <Button type="submit" variant="contained" disabled={isLoading || uppyFiles.length === 0}>
            {isLoading ? 'Uploading...' : uppyFiles.length <= 1 ? 'Upload' : `Upload ${uppyFiles.length} files`}
          </Button>
        </DialogActions>
      </form>
    </Dialog>
  );
};

export { UploadAssetDialog };
