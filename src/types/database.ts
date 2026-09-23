/**
 * Tipe database — ringkas.
 * Versi lengkap digenerate otomatis:  npm run db:types
 *   (supabase gen types typescript --local > src/types/database.ts)
 */

export type UserRole = 'user' | 'admin' | 'super_admin' | 'support' | 'finance';
export type WebsiteStatus = 'draft' | 'active' | 'payment_due' | 'grace_period' | 'suspended' | 'expired';
export type SubscriptionStatus = 'trial' | 'active' | 'past_due' | 'cancelled' | 'expired' | 'suspended';
export type PaymentStatus = 'pending' | 'paid' | 'failed' | 'refunded' | 'expired';
export type InvoiceStatus = 'draft' | 'pending' | 'paid' | 'failed' | 'refunded' | 'cancelled';
export type DomainStatus = 'pending' | 'verifying' | 'active' | 'failed' | 'expired';
export type TicketStatus = 'open' | 'pending' | 'resolved' | 'closed';

export interface Profile {
  id: string;
  full_name: string | null;
  avatar_url: string | null;
  phone: string | null;
  created_at: string;
  updated_at: string;
}

export interface Plan {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  price_monthly: number;
  price_yearly: number | null;
  currency: string;
  storage_mb: number;
  max_pages: number | null;
  custom_domain: boolean;
  analytics: boolean;
  seo_tools: boolean;
  support_level: string;
  is_active: boolean;
  sort_order: number;
}

export interface Template {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  category_id: string | null;
  thumbnail_url: string | null;
  preview_url: string | null;
  required_plan_id: string | null;
  status: 'draft' | 'published' | 'archived';
}

export interface Website {
  id: string;
  user_id: string;
  template_id: string | null;
  name: string;
  slug: string;
  subdomain: string;
  status: WebsiteStatus;
  theme: Record<string, unknown>;
  expires_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface WebsitePage {
  id: string;
  website_id: string;
  title: string;
  slug: string;
  is_home: boolean;
  status: 'draft' | 'published';
  seo: Record<string, unknown>;
  sort_order: number;
}

export interface WebsiteSection {
  id: string;
  page_id: string;
  type: 'hero' | 'text' | 'image' | 'button' | 'gallery' | 'services' | 'products' | 'pricing' | 'testimonials' | 'faq' | 'contact' | 'map' | 'video' | 'social_links' | 'cta' | 'footer';
  content: Record<string, unknown>;
  style: Record<string, unknown>;
  sort_order: number;
  is_visible: boolean;
}

export interface Subscription {
  id: string;
  user_id: string;
  website_id: string | null;
  plan_id: string;
  coupon_id: string | null;
  status: SubscriptionStatus;
  billing_period: 'monthly' | 'yearly';
  current_period_start: string;
  current_period_end: string;
  cancel_at_period_end: boolean;
}

export interface Invoice {
  id: string;
  user_id: string;
  subscription_id: string | null;
  number: string;
  status: InvoiceStatus;
  issue_date: string;
  due_date: string;
  paid_at: string | null;
  subtotal: number;
  discount: number;
  total: number;
  currency: string;
}

export interface Payment {
  id: string;
  user_id: string;
  invoice_id: string | null;
  subscription_id: string | null;
  amount: number;
  currency: string;
  gateway: string;
  gateway_ref: string | null;
  payment_method: string | null;
  status: PaymentStatus;
  paid_at: string | null;
}

export interface Domain {
  id: string;
  website_id: string;
  domain: string;
  is_primary: boolean;
  status: DomainStatus;
  dns_token: string;
  verified_at: string | null;
}

export interface Ticket {
  id: string;
  user_id: string;
  website_id: string | null;
  subject: string;
  category: string;
  status: TicketStatus;
  priority: string;
  created_at: string;
}

export interface Notification {
  id: string;
  user_id: string | null;
  title: string;
  body: string | null;
  type: string;
  channel: 'dashboard' | 'email' | 'whatsapp';
  is_read: boolean;
  created_at: string;
}

export interface ActivityLog {
  id: string;
  actor_id: string | null;
  actor_role: string | null;
  action: string;
  target_type: string | null;
  target_id: string | null;
  ip: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
}
