import '@mui/material/Button';

declare module '@mui/material/Button' {
  interface ButtonPropsVariantOverrides {
    flat: true;
  }
}

declare module '@mui/material/styles' {
  interface TypographyVariants {
    displayMedium: React.CSSProperties;
    displaySmall: React.CSSProperties;
    bodySmall: React.CSSProperties;
    bodyMedium: React.CSSProperties;
    bodyLarge: React.CSSProperties;
    labelLarge: React.CSSProperties;
    labelMedium: React.CSSProperties;
    labelSmall: React.CSSProperties;
    titleSmall: React.CSSProperties;
    titleMedium: React.CSSProperties;
  }

  // allow configuration using `createTheme()`
  interface TypographyVariantsOptions {
    bodySmall?: React.CSSProperties;
    displayMedium?: React.CSSProperties;
    displaySmall?: React.CSSProperties;
    bodySmall?: React.CSSProperties;
    bodyLarge?: React.CSSProperties;
    bodyMedium?: React.CSSProperties;
    labelLarge?: React.CSSProperties;
    labelMedium?: React.CSSProperties;
    labelSmall?: React.CSSProperties;
    titleSmall?: React.CSSProperties;
    titleMedium?: React.CSSProperties;
  }
}

// Update the Typography's variant prop options
declare module '@mui/material/Typography' {
  interface TypographyPropsVariantOverrides {
    bodySmall: true;
    displayMedium: true;
    displaySmall: true;
    bodyLarge: true;
    bodyMedium: true;
    labelLarge: true;
    labelMedium: true;
    labelSmall: true;
    titleSmall: true;
    titleMedium: true;
  }
}
