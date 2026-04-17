import { Page } from '@playwright/test';

const BASE_URL = process.env.STAGING_URL ?? 'https://staging.aixle.com';
const HTTP_CREDENTIALS = {
  username: process.env.STAGING_HTTP_USER ?? 'admin',
  password: process.env.STAGING_HTTP_PASSWORD ?? '',
};

export interface LoginCredentials {
  email: string;
  password: string;
}

export const CREDENTIALS = {
  admin: {
    email: process.env.STAGING_ADMIN_EMAIL ?? 'admin-agent@aixle.com',
    password: process.env.STAGING_ADMIN_PASSWORD ?? '',
  },
  companyAdmin: {
    email: process.env.STAGING_COMPANY_ADMIN_EMAIL ?? 'admin-atc@staging.aixle.com',
    password: process.env.STAGING_COMPANY_ADMIN_PASSWORD ?? '',
  },
  companyEmployee: {
    email: process.env.STAGING_EMPLOYEE_EMAIL ?? 'employee-atc@staging.aixle.com',
    password: process.env.STAGING_EMPLOYEE_PASSWORD ?? '',
  },
} as const;

/**
 * Log in using the provided credentials.
 * Handles HTTP Basic Auth for the staging environment automatically.
 * Waits until redirected away from /login after successful authentication.
 */
export async function login(page: Page, credentials: LoginCredentials): Promise<void> {
  await page.context().setHTTPCredentials(HTTP_CREDENTIALS);

  await page.goto(`${BASE_URL}/login`, { waitUntil: 'domcontentloaded' });

  await page.locator('input[name="email"]').fill(credentials.email);
  await page.locator('input[name="password"]').fill(credentials.password);
  await page.getByRole('button', { name: 'Sign in' }).click();

  await page.waitForURL((url) => !url.pathname.startsWith('/login'), { timeout: 30000 });
}

/**
 * Log in as Admin (admin-agent@aixle.com).
 */
export async function loginAsAdmin(page: Page): Promise<void> {
  await login(page, CREDENTIALS.admin);
}

/**
 * Log in as Company Admin (admin-atc@staging.aixle.com).
 */
export async function loginAsCompanyAdmin(page: Page): Promise<void> {
  await login(page, CREDENTIALS.companyAdmin);
}

/**
 * Log in as Company Employee (employee-atc@staging.aixle.com).
 */
export async function loginAsCompanyEmployee(page: Page): Promise<void> {
  await login(page, CREDENTIALS.companyEmployee);
}

export { BASE_URL, HTTP_CREDENTIALS };
