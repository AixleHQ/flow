import data from '@emoji-mart/data';
import Picker from '@emoji-mart/react';
import { Box, IconButton, Popover, type SxProps } from '@mui/material';
import { useState, type FC, type MouseEvent } from 'react';

interface EmojiPickerProps {
  value: string;
  onChange: (emoji: string) => void;
  disabled?: boolean;
}

interface EmojiData {
  native: string;
}

const styles = {
  button: {
    width: 56,
    height: 56,
    fontSize: 28,
    border: '1px solid',
    borderColor: 'rgba(255, 255, 255, 0.23)',
    borderRadius: 1,
    backgroundColor: 'transparent',
    mt: '8px', // align with TextField input (after label)
    '&:hover': {
      borderColor: 'rgba(255, 255, 255, 0.5)',
      backgroundColor: 'rgba(255, 255, 255, 0.05)',
    },
  },
  placeholder: {
    width: 56,
    height: 56,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: 12,
    color: 'text.disabled',
    border: '1px dashed',
    borderColor: 'rgba(255, 255, 255, 0.23)',
    borderRadius: 1,
    cursor: 'pointer',
    mt: '8px', // align with TextField input (after label)
    '&:hover': {
      borderColor: 'primary.main',
      color: 'primary.main',
    },
  },
} satisfies Record<string, SxProps>;

const EmojiPicker: FC<EmojiPickerProps> = ({ value, onChange, disabled }) => {
  const [anchorEl, setAnchorEl] = useState<HTMLElement | null>(null);

  const handleClick = (event: MouseEvent<HTMLElement>) => {
    if (!disabled) {
      setAnchorEl(event.currentTarget);
    }
  };

  const handleClose = () => {
    setAnchorEl(null);
  };

  const handleEmojiSelect = (emoji: EmojiData) => {
    onChange(emoji.native);
    handleClose();
  };

  const open = Boolean(anchorEl);

  return (
    <>
      {value ? (
        <IconButton onClick={handleClick} disabled={disabled} sx={styles.button}>
          {value}
        </IconButton>
      ) : (
        <Box onClick={handleClick} sx={{ ...styles.placeholder, pointerEvents: disabled ? 'none' : 'auto' }}>
          Icon
        </Box>
      )}
      <Popover
        open={open}
        anchorEl={anchorEl}
        onClose={handleClose}
        anchorOrigin={{
          vertical: 'bottom',
          horizontal: 'left',
        }}
        transformOrigin={{
          vertical: 'top',
          horizontal: 'left',
        }}
      >
        <Picker
          data={data}
          onEmojiSelect={handleEmojiSelect}
          theme="dark"
          previewPosition="none"
          skinTonePosition="search"
        />
      </Popover>
    </>
  );
};

export { EmojiPicker };
