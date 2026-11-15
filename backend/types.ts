/* eslint-disable */
// AUTO-GENERATED — DO NOT EDIT
// Run migrations to regenerate.

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.17"
  }
  public: {
    Tables: {
      addresses: {
        Row: {
          access_notes: string | null
          city: string
          company_id: string
          created_at: string
          customer_id: string
          id: string
          is_default: boolean
          latitude: number
          line1: string
          line2: string | null
          longitude: number
          postal_code: string
          state: string
          updated_at: string
        }
        Insert: {
          access_notes?: string | null
          city?: string
          company_id: string
          created_at?: string
          customer_id: string
          id?: string
          is_default?: boolean
          latitude?: number
          line1: string
          line2?: string | null
          longitude?: number
          postal_code?: string
          state?: string
          updated_at?: string
        }
        Update: {
          access_notes?: string | null
          city?: string
          company_id?: string
          created_at?: string
          customer_id?: string
          id?: string
          is_default?: boolean
          latitude?: number
          line1?: string
          line2?: string | null
          longitude?: number
          postal_code?: string
          state?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "addresses_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "addresses_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "addresses_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
        ]
      }
      app_users: {
        Row: {
          avatar_url: string | null
          company_id: string
          created_at: string
          duty_state: Database["public"]["Enums"]["worker_duty_state"]
          duty_state_changed_at: string | null
          email: string
          id: string
          invited_by_user_id: string | null
          last_active_at: string | null
          name: string
          phone: string
          role: Database["public"]["Enums"]["app_role"]
          status: Database["public"]["Enums"]["app_user_status"]
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          company_id: string
          created_at?: string
          duty_state?: Database["public"]["Enums"]["worker_duty_state"]
          duty_state_changed_at?: string | null
          email: string
          id: string
          invited_by_user_id?: string | null
          last_active_at?: string | null
          name?: string
          phone?: string
          role: Database["public"]["Enums"]["app_role"]
          status?: Database["public"]["Enums"]["app_user_status"]
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          company_id?: string
          created_at?: string
          duty_state?: Database["public"]["Enums"]["worker_duty_state"]
          duty_state_changed_at?: string | null
          email?: string
          id?: string
          invited_by_user_id?: string | null
          last_active_at?: string | null
          name?: string
          phone?: string
          role?: Database["public"]["Enums"]["app_role"]
          status?: Database["public"]["Enums"]["app_user_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "app_users_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "app_users_invited_by_user_id_fkey"
            columns: ["invited_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      apple_notifications: {
        Row: {
          company_id: string | null
          environment: string | null
          notification_type: string
          notification_uuid: string
          original_transaction_id: string | null
          outcome: string | null
          received_at: string
          signed_at: string | null
          subtype: string | null
        }
        Insert: {
          company_id?: string | null
          environment?: string | null
          notification_type: string
          notification_uuid: string
          original_transaction_id?: string | null
          outcome?: string | null
          received_at?: string
          signed_at?: string | null
          subtype?: string | null
        }
        Update: {
          company_id?: string | null
          environment?: string | null
          notification_type?: string
          notification_uuid?: string
          original_transaction_id?: string | null
          outcome?: string | null
          received_at?: string
          signed_at?: string | null
          subtype?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "apple_notifications_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      apple_sandbox_companies: {
        Row: {
          added_at: string
          company_id: string
          note: string
        }
        Insert: {
          added_at?: string
          company_id: string
          note?: string
        }
        Update: {
          added_at?: string
          company_id?: string
          note?: string
        }
        Relationships: [
          {
            foreignKeyName: "apple_sandbox_companies_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: true
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      apple_transactions: {
        Row: {
          company_id: string | null
          created_at: string
          environment: string
          expires_at: string | null
          offer_discount_type: string | null
          offer_identifier: string | null
          offer_type: number | null
          original_transaction_id: string
          product_id: string
          purchase_at: string | null
          revoked_at: string | null
          signed_at: string | null
          source: string
          transaction_id: string
          updated_at: string
        }
        Insert: {
          company_id?: string | null
          created_at?: string
          environment: string
          expires_at?: string | null
          offer_discount_type?: string | null
          offer_identifier?: string | null
          offer_type?: number | null
          original_transaction_id: string
          product_id: string
          purchase_at?: string | null
          revoked_at?: string | null
          signed_at?: string | null
          source: string
          transaction_id: string
          updated_at?: string
        }
        Update: {
          company_id?: string | null
          created_at?: string
          environment?: string
          expires_at?: string | null
          offer_discount_type?: string | null
          offer_identifier?: string | null
          offer_type?: number | null
          original_transaction_id?: string
          product_id?: string
          purchase_at?: string | null
          revoked_at?: string | null
          signed_at?: string | null
          source?: string
          transaction_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "apple_transactions_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      chat_blocked_terms: {
        Row: {
          active: boolean
          category: string
          created_at: string
          term: string
        }
        Insert: {
          active?: boolean
          category?: string
          created_at?: string
          term: string
        }
        Update: {
          active?: boolean
          category?: string
          created_at?: string
          term?: string
        }
        Relationships: []
      }
      chat_blocks: {
        Row: {
          blocked_user_id: string
          blocker_user_id: string
          company_id: string
          created_at: string
          report_id: string | null
        }
        Insert: {
          blocked_user_id: string
          blocker_user_id: string
          company_id: string
          created_at?: string
          report_id?: string | null
        }
        Update: {
          blocked_user_id?: string
          blocker_user_id?: string
          company_id?: string
          created_at?: string
          report_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "chat_blocks_blocked_user_id_fkey"
            columns: ["blocked_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_blocks_blocker_user_id_fkey"
            columns: ["blocker_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_blocks_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_blocks_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: false
            referencedRelation: "message_reports"
            referencedColumns: ["id"]
          },
        ]
      }
      chat_restrictions: {
        Row: {
          company_id: string
          created_at: string
          expires_at: string | null
          lifted_at: string | null
          lifted_by_user_id: string | null
          reason: string | null
          report_id: string | null
          restricted_by_user_id: string | null
          user_id: string
        }
        Insert: {
          company_id: string
          created_at?: string
          expires_at?: string | null
          lifted_at?: string | null
          lifted_by_user_id?: string | null
          reason?: string | null
          report_id?: string | null
          restricted_by_user_id?: string | null
          user_id: string
        }
        Update: {
          company_id?: string
          created_at?: string
          expires_at?: string | null
          lifted_at?: string | null
          lifted_by_user_id?: string | null
          reason?: string | null
          report_id?: string | null
          restricted_by_user_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "chat_restrictions_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_restrictions_lifted_by_user_id_fkey"
            columns: ["lifted_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_restrictions_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: false
            referencedRelation: "message_reports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_restrictions_restricted_by_user_id_fkey"
            columns: ["restricted_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chat_restrictions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      companies: {
        Row: {
          address_line: string
          business_email: string | null
          city: string
          closed_at: string | null
          country_code: string
          created_at: string
          currency_code: string
          default_payment_terms_days: number
          default_payment_terms_label: string
          default_tax_rate: number
          id: string
          name: string
          online_payment_link_url: string | null
          phone: string
          postal_code: string
          state: string
          time_zone_identifier: string
          trade: Database["public"]["Enums"]["app_trade"]
          updated_at: string
        }
        Insert: {
          address_line?: string
          business_email?: string | null
          city?: string
          closed_at?: string | null
          country_code: string
          created_at?: string
          currency_code: string
          default_payment_terms_days?: number
          default_payment_terms_label?: string
          default_tax_rate?: number
          id?: string
          name: string
          online_payment_link_url?: string | null
          phone?: string
          postal_code?: string
          state?: string
          time_zone_identifier: string
          trade: Database["public"]["Enums"]["app_trade"]
          updated_at?: string
        }
        Update: {
          address_line?: string
          business_email?: string | null
          city?: string
          closed_at?: string | null
          country_code?: string
          created_at?: string
          currency_code?: string
          default_payment_terms_days?: number
          default_payment_terms_label?: string
          default_tax_rate?: number
          id?: string
          name?: string
          online_payment_link_url?: string | null
          phone?: string
          postal_code?: string
          state?: string
          time_zone_identifier?: string
          trade?: Database["public"]["Enums"]["app_trade"]
          updated_at?: string
        }
        Relationships: []
      }
      company_messaging_accounts: {
        Row: {
          address_sid: string | null
          auth_token_secret_id: string | null
          billing_state: string
          brand_identity_status: string | null
          brand_sid: string | null
          brand_status: string | null
          business_details: Json
          business_end_user_sid: string | null
          callback_key: string
          campaign_sid: string | null
          campaign_status: string | null
          closed_at: string | null
          closing_started_at: string | null
          company_id: string
          created_at: string
          created_by_user_id: string | null
          customer_profile_sid: string | null
          grace_started_at: string | null
          id: string
          last_error: string | null
          last_error_at: string | null
          messaging_service_sid: string | null
          next_attempt_at: string | null
          provisioning_step: string
          registration_error: string | null
          registration_route: string | null
          registration_status: string
          representative_end_user_sid: string | null
          requested_area_code: string | null
          requested_number: string | null
          retention_until: string | null
          retry_count: number
          status: string
          supporting_document_sid: string | null
          suspended_at: string | null
          suspended_reason: string | null
          trust_end_user_sid: string | null
          trust_product_sid: string | null
          twilio_subaccount_sid: string | null
          updated_at: string
        }
        Insert: {
          address_sid?: string | null
          auth_token_secret_id?: string | null
          billing_state?: string
          brand_identity_status?: string | null
          brand_sid?: string | null
          brand_status?: string | null
          business_details?: Json
          business_end_user_sid?: string | null
          callback_key?: string
          campaign_sid?: string | null
          campaign_status?: string | null
          closed_at?: string | null
          closing_started_at?: string | null
          company_id: string
          created_at?: string
          created_by_user_id?: string | null
          customer_profile_sid?: string | null
          grace_started_at?: string | null
          id?: string
          last_error?: string | null
          last_error_at?: string | null
          messaging_service_sid?: string | null
          next_attempt_at?: string | null
          provisioning_step?: string
          registration_error?: string | null
          registration_route?: string | null
          registration_status?: string
          representative_end_user_sid?: string | null
          requested_area_code?: string | null
          requested_number?: string | null
          retention_until?: string | null
          retry_count?: number
          status?: string
          supporting_document_sid?: string | null
          suspended_at?: string | null
          suspended_reason?: string | null
          trust_end_user_sid?: string | null
          trust_product_sid?: string | null
          twilio_subaccount_sid?: string | null
          updated_at?: string
        }
        Update: {
          address_sid?: string | null
          auth_token_secret_id?: string | null
          billing_state?: string
          brand_identity_status?: string | null
          brand_sid?: string | null
          brand_status?: string | null
          business_details?: Json
          business_end_user_sid?: string | null
          callback_key?: string
          campaign_sid?: string | null
          campaign_status?: string | null
          closed_at?: string | null
          closing_started_at?: string | null
          company_id?: string
          created_at?: string
          created_by_user_id?: string | null
          customer_profile_sid?: string | null
          grace_started_at?: string | null
          id?: string
          last_error?: string | null
          last_error_at?: string | null
          messaging_service_sid?: string | null
          next_attempt_at?: string | null
          provisioning_step?: string
          registration_error?: string | null
          registration_route?: string | null
          registration_status?: string
          representative_end_user_sid?: string | null
          requested_area_code?: string | null
          requested_number?: string | null
          retention_until?: string | null
          retry_count?: number
          status?: string
          supporting_document_sid?: string | null
          suspended_at?: string | null
          suspended_reason?: string | null
          trust_end_user_sid?: string | null
          trust_product_sid?: string | null
          twilio_subaccount_sid?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "company_messaging_accounts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: true
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_messaging_accounts_created_by_user_id_fkey"
            columns: ["created_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      company_phone_numbers: {
        Row: {
          area_code: string | null
          company_id: string
          created_at: string
          e164: string
          id: string
          is_primary: boolean
          last_fee_charged_at: string | null
          locality: string | null
          messaging_account_id: string
          monthly_fee_credits: number
          next_fee_due_at: string | null
          phone_number_sid: string | null
          purchased_at: string | null
          region: string | null
          release_confirmed_at: string | null
          release_confirmed_by: string | null
          release_reason: string | null
          released_at: string | null
          status: string
          updated_at: string
        }
        Insert: {
          area_code?: string | null
          company_id: string
          created_at?: string
          e164: string
          id?: string
          is_primary?: boolean
          last_fee_charged_at?: string | null
          locality?: string | null
          messaging_account_id: string
          monthly_fee_credits?: number
          next_fee_due_at?: string | null
          phone_number_sid?: string | null
          purchased_at?: string | null
          region?: string | null
          release_confirmed_at?: string | null
          release_confirmed_by?: string | null
          release_reason?: string | null
          released_at?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          area_code?: string | null
          company_id?: string
          created_at?: string
          e164?: string
          id?: string
          is_primary?: boolean
          last_fee_charged_at?: string | null
          locality?: string | null
          messaging_account_id?: string
          monthly_fee_credits?: number
          next_fee_due_at?: string | null
          phone_number_sid?: string | null
          purchased_at?: string | null
          region?: string | null
          release_confirmed_at?: string | null
          release_confirmed_by?: string | null
          release_reason?: string | null
          released_at?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "company_phone_numbers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_phone_numbers_messaging_account_id_fkey"
            columns: ["messaging_account_id"]
            isOneToOne: false
            referencedRelation: "company_messaging_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_phone_numbers_release_confirmed_by_fkey"
            columns: ["release_confirmed_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      company_subscriptions: {
        Row: {
          active_paid_users: number
          additional_user_cents: number
          additional_users: number
          apple_auto_renew: boolean | null
          apple_auto_renew_product_id: string | null
          apple_environment: string | null
          apple_expiration_intent: number | null
          apple_expires_at: string | null
          apple_grace_period_expires_at: string | null
          apple_in_billing_retry: boolean
          apple_is_free_offer: boolean
          apple_last_transaction_id: string | null
          apple_offer_discount_type: string | null
          apple_offer_identifier: string | null
          apple_offer_period: string | null
          apple_offer_type: number | null
          apple_original_transaction_id: string | null
          apple_product_id: string | null
          apple_purchase_at: string | null
          apple_renewal_signed_at: string | null
          apple_revoked_at: string | null
          apple_synced_at: string | null
          base_cents: number
          billing_period: Database["public"]["Enums"]["billing_period"]
          cancelled_at: string | null
          company_id: string
          created_at: string
          current_period_end: string
          current_period_start: string
          google_purchase_token: string | null
          id: string
          included_users: number
          is_trial: boolean
          last_payment_failed_at: string | null
          last_payment_failure: string | null
          monthly_price_cents: number
          past_due_since: string | null
          payment_model: Database["public"]["Enums"]["company_payment_model"]
          plan: Database["public"]["Enums"]["subscription_plan"]
          renewal_date: string
          seat_count: number
          seats_synced_at: string | null
          status: Database["public"]["Enums"]["subscription_status"]
          store: Database["public"]["Enums"]["billing_store"]
          stripe_customer_id: string | null
          stripe_price_id: string | null
          stripe_subscription_id: string | null
          tier_id: string | null
          trial_ends_at: string | null
          updated_at: string
        }
        Insert: {
          active_paid_users?: number
          additional_user_cents?: number
          additional_users?: number
          apple_auto_renew?: boolean | null
          apple_auto_renew_product_id?: string | null
          apple_environment?: string | null
          apple_expiration_intent?: number | null
          apple_expires_at?: string | null
          apple_grace_period_expires_at?: string | null
          apple_in_billing_retry?: boolean
          apple_is_free_offer?: boolean
          apple_last_transaction_id?: string | null
          apple_offer_discount_type?: string | null
          apple_offer_identifier?: string | null
          apple_offer_period?: string | null
          apple_offer_type?: number | null
          apple_original_transaction_id?: string | null
          apple_product_id?: string | null
          apple_purchase_at?: string | null
          apple_renewal_signed_at?: string | null
          apple_revoked_at?: string | null
          apple_synced_at?: string | null
          base_cents?: number
          billing_period?: Database["public"]["Enums"]["billing_period"]
          cancelled_at?: string | null
          company_id: string
          created_at?: string
          current_period_end?: string
          current_period_start?: string
          google_purchase_token?: string | null
          id?: string
          included_users?: number
          is_trial?: boolean
          last_payment_failed_at?: string | null
          last_payment_failure?: string | null
          monthly_price_cents?: number
          past_due_since?: string | null
          payment_model?: Database["public"]["Enums"]["company_payment_model"]
          plan?: Database["public"]["Enums"]["subscription_plan"]
          renewal_date?: string
          seat_count?: number
          seats_synced_at?: string | null
          status?: Database["public"]["Enums"]["subscription_status"]
          store?: Database["public"]["Enums"]["billing_store"]
          stripe_customer_id?: string | null
          stripe_price_id?: string | null
          stripe_subscription_id?: string | null
          tier_id?: string | null
          trial_ends_at?: string | null
          updated_at?: string
        }
        Update: {
          active_paid_users?: number
          additional_user_cents?: number
          additional_users?: number
          apple_auto_renew?: boolean | null
          apple_auto_renew_product_id?: string | null
          apple_environment?: string | null
          apple_expiration_intent?: number | null
          apple_expires_at?: string | null
          apple_grace_period_expires_at?: string | null
          apple_in_billing_retry?: boolean
          apple_is_free_offer?: boolean
          apple_last_transaction_id?: string | null
          apple_offer_discount_type?: string | null
          apple_offer_identifier?: string | null
          apple_offer_period?: string | null
          apple_offer_type?: number | null
          apple_original_transaction_id?: string | null
          apple_product_id?: string | null
          apple_purchase_at?: string | null
          apple_renewal_signed_at?: string | null
          apple_revoked_at?: string | null
          apple_synced_at?: string | null
          base_cents?: number
          billing_period?: Database["public"]["Enums"]["billing_period"]
          cancelled_at?: string | null
          company_id?: string
          created_at?: string
          current_period_end?: string
          current_period_start?: string
          google_purchase_token?: string | null
          id?: string
          included_users?: number
          is_trial?: boolean
          last_payment_failed_at?: string | null
          last_payment_failure?: string | null
          monthly_price_cents?: number
          past_due_since?: string | null
          payment_model?: Database["public"]["Enums"]["company_payment_model"]
          plan?: Database["public"]["Enums"]["subscription_plan"]
          renewal_date?: string
          seat_count?: number
          seats_synced_at?: string | null
          status?: Database["public"]["Enums"]["subscription_status"]
          store?: Database["public"]["Enums"]["billing_store"]
          stripe_customer_id?: string | null
          stripe_price_id?: string | null
          stripe_subscription_id?: string | null
          tier_id?: string | null
          trial_ends_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "company_subscriptions_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: true
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "company_subscriptions_tier_id_fkey"
            columns: ["tier_id"]
            isOneToOne: false
            referencedRelation: "subscription_tiers"
            referencedColumns: ["id"]
          },
        ]
      }
      customer_contacts: {
        Row: {
          company_id: string
          contact_role: string
          created_at: string
          customer_id: string
          email: string | null
          id: string
          is_billing_contact: boolean
          is_primary: boolean
          name: string
          phone: string
          updated_at: string
        }
        Insert: {
          company_id: string
          contact_role?: string
          created_at?: string
          customer_id: string
          email?: string | null
          id?: string
          is_billing_contact?: boolean
          is_primary?: boolean
          name: string
          phone?: string
          updated_at?: string
        }
        Update: {
          company_id?: string
          contact_role?: string
          created_at?: string
          customer_id?: string
          email?: string | null
          id?: string
          is_billing_contact?: boolean
          is_primary?: boolean
          name?: string
          phone?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "customer_contacts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_contacts_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_contacts_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
        ]
      }
      customers: {
        Row: {
          billing_terms: string
          company_id: string
          created_at: string
          id: string
          name: string
          notes: string | null
          status: Database["public"]["Enums"]["customer_status"]
          type: Database["public"]["Enums"]["customer_type"]
          updated_at: string
        }
        Insert: {
          billing_terms?: string
          company_id: string
          created_at?: string
          id?: string
          name: string
          notes?: string | null
          status?: Database["public"]["Enums"]["customer_status"]
          type?: Database["public"]["Enums"]["customer_type"]
          updated_at?: string
        }
        Update: {
          billing_terms?: string
          company_id?: string
          created_at?: string
          id?: string
          name?: string
          notes?: string | null
          status?: Database["public"]["Enums"]["customer_status"]
          type?: Database["public"]["Enums"]["customer_type"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "customers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      document_sequences: {
        Row: {
          company_id: string
          created_at: string
          id: string
          kind: Database["public"]["Enums"]["document_kind"]
          next_value: number
          pad_width: number
          prefix: string
          updated_at: string
        }
        Insert: {
          company_id: string
          created_at?: string
          id?: string
          kind: Database["public"]["Enums"]["document_kind"]
          next_value?: number
          pad_width?: number
          prefix?: string
          updated_at?: string
        }
        Update: {
          company_id?: string
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["document_kind"]
          next_value?: number
          pad_width?: number
          prefix?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "document_sequences_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      equipment: {
        Row: {
          address_id: string
          attributes: Json
          category: string
          company_id: string
          created_at: string
          customer_id: string | null
          id: string
          installed_on: string
          is_active: boolean
          make: string
          model: string
          photo_url: string | null
          serial_number: string
          updated_at: string
          warranty_expires_on: string | null
        }
        Insert: {
          address_id: string
          attributes?: Json
          category?: string
          company_id: string
          created_at?: string
          customer_id?: string | null
          id?: string
          installed_on: string
          is_active?: boolean
          make?: string
          model?: string
          photo_url?: string | null
          serial_number?: string
          updated_at?: string
          warranty_expires_on?: string | null
        }
        Update: {
          address_id?: string
          attributes?: Json
          category?: string
          company_id?: string
          created_at?: string
          customer_id?: string | null
          id?: string
          installed_on?: string
          is_active?: boolean
          make?: string
          model?: string
          photo_url?: string | null
          serial_number?: string
          updated_at?: string
          warranty_expires_on?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "equipment_address_id_fkey"
            columns: ["address_id"]
            isOneToOne: false
            referencedRelation: "addresses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "equipment_address_id_fkey"
            columns: ["address_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["address_id"]
          },
          {
            foreignKeyName: "equipment_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      equipment_history: {
        Row: {
          company_id: string
          created_at: string
          equipment_id: string
          id: string
          job_id: string | null
          occurred_at: string
          summary: string
        }
        Insert: {
          company_id: string
          created_at?: string
          equipment_id: string
          id?: string
          job_id?: string | null
          occurred_at: string
          summary?: string
        }
        Update: {
          company_id?: string
          created_at?: string
          equipment_id?: string
          id?: string
          job_id?: string | null
          occurred_at?: string
          summary?: string
        }
        Relationships: [
          {
            foreignKeyName: "equipment_history_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "equipment_history_equipment_id_fkey"
            columns: ["equipment_id"]
            isOneToOne: false
            referencedRelation: "equipment"
            referencedColumns: ["id"]
          },
        ]
      }
      field_worker_assignments: {
        Row: {
          accepted_at: string | null
          assigned_at: string
          assigned_by_user_id: string
          company_id: string
          id: string
          is_primary: boolean
          job_id: string
          sort_order: number
          user_id: string
        }
        Insert: {
          accepted_at?: string | null
          assigned_at?: string
          assigned_by_user_id: string
          company_id: string
          id?: string
          is_primary?: boolean
          job_id: string
          sort_order?: number
          user_id: string
        }
        Update: {
          accepted_at?: string | null
          assigned_at?: string
          assigned_by_user_id?: string
          company_id?: string
          id?: string
          is_primary?: boolean
          job_id?: string
          sort_order?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "field_worker_assignments_assigned_by_user_id_fkey"
            columns: ["assigned_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "field_worker_assignments_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "field_worker_assignments_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "field_worker_assignments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      field_worker_locations: {
        Row: {
          accuracy_meters: number
          capture_event:
            | Database["public"]["Enums"]["location_capture_event"]
            | null
          company_id: string
          heading: number | null
          id: string
          is_simulated: boolean
          job_id: string | null
          latitude: number
          longitude: number
          recorded_at: string
          speed_meters_per_second: number | null
          user_id: string
        }
        Insert: {
          accuracy_meters?: number
          capture_event?:
            | Database["public"]["Enums"]["location_capture_event"]
            | null
          company_id: string
          heading?: number | null
          id?: string
          is_simulated?: boolean
          job_id?: string | null
          latitude: number
          longitude: number
          recorded_at?: string
          speed_meters_per_second?: number | null
          user_id: string
        }
        Update: {
          accuracy_meters?: number
          capture_event?:
            | Database["public"]["Enums"]["location_capture_event"]
            | null
          company_id?: string
          heading?: number | null
          id?: string
          is_simulated?: boolean
          job_id?: string | null
          latitude?: number
          longitude?: number
          recorded_at?: string
          speed_meters_per_second?: number | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "field_worker_locations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "field_worker_locations_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "field_worker_locations_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      founding_member_slots: {
        Row: {
          claimed_at: string | null
          company_id: string | null
          number: number
        }
        Insert: {
          claimed_at?: string | null
          company_id?: string | null
          number: number
        }
        Update: {
          claimed_at?: string | null
          company_id?: string | null
          number?: number
        }
        Relationships: [
          {
            foreignKeyName: "founding_member_slots_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: true
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      invitations: {
        Row: {
          accepted_at: string | null
          accepted_by_user_id: string | null
          company_id: string
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by_user_id: string
          revoked_at: string | null
          role: Database["public"]["Enums"]["app_role"]
          token: string
        }
        Insert: {
          accepted_at?: string | null
          accepted_by_user_id?: string | null
          company_id: string
          created_at?: string
          email: string
          expires_at: string
          id?: string
          invited_by_user_id: string
          revoked_at?: string | null
          role: Database["public"]["Enums"]["app_role"]
          token: string
        }
        Update: {
          accepted_at?: string | null
          accepted_by_user_id?: string | null
          company_id?: string
          created_at?: string
          email?: string
          expires_at?: string
          id?: string
          invited_by_user_id?: string
          revoked_at?: string | null
          role?: Database["public"]["Enums"]["app_role"]
          token?: string
        }
        Relationships: [
          {
            foreignKeyName: "invitations_accepted_by_user_id_fkey"
            columns: ["accepted_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invitations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invitations_invited_by_user_id_fkey"
            columns: ["invited_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      invoice_line_items: {
        Row: {
          company_id: string
          id: string
          invoice_id: string
          item_description: string
          line_total: number
          quantity: number
          sort_order: number
          source_quote_line_item_id: string | null
          tax_rate: number
          unit_price: number
        }
        Insert: {
          company_id: string
          id?: string
          invoice_id: string
          item_description?: string
          line_total?: number
          quantity?: number
          sort_order?: number
          source_quote_line_item_id?: string | null
          tax_rate?: number
          unit_price?: number
        }
        Update: {
          company_id?: string
          id?: string
          invoice_id?: string
          item_description?: string
          line_total?: number
          quantity?: number
          sort_order?: number
          source_quote_line_item_id?: string | null
          tax_rate?: number
          unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: "invoice_line_items_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_line_items_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_line_items_source_quote_line_item_id_fkey"
            columns: ["source_quote_line_item_id"]
            isOneToOne: false
            referencedRelation: "quote_line_items"
            referencedColumns: ["id"]
          },
        ]
      }
      invoice_share_tokens: {
        Row: {
          company_id: string
          created_at: string
          created_by_user_id: string
          expires_at: string | null
          id: string
          invoice_id: string
          last_viewed_at: string | null
          revoked_at: string | null
          token: string
          view_count: number
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by_user_id: string
          expires_at?: string | null
          id?: string
          invoice_id: string
          last_viewed_at?: string | null
          revoked_at?: string | null
          token: string
          view_count?: number
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by_user_id?: string
          expires_at?: string | null
          id?: string
          invoice_id?: string
          last_viewed_at?: string | null
          revoked_at?: string | null
          token?: string
          view_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "invoice_share_tokens_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_share_tokens_created_by_user_id_fkey"
            columns: ["created_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_share_tokens_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      invoices: {
        Row: {
          address_id: string | null
          amount_paid: number
          balance: number
          billing_contact_id: string | null
          company_id: string
          created_at: string
          created_by_user_id: string | null
          currency_code: string
          customer_id: string
          due_date: string
          id: string
          issue_date: string
          job_id: string | null
          number: string
          paid_at: string | null
          payment_terms_label: string
          quote_id: string | null
          scope_of_work: string
          sent_at: string | null
          status: Database["public"]["Enums"]["invoice_status"]
          subtotal: number
          tax: number
          title: string
          total: number
          updated_at: string
          viewed_at: string | null
          voided_at: string | null
        }
        Insert: {
          address_id?: string | null
          amount_paid?: number
          balance?: number
          billing_contact_id?: string | null
          company_id: string
          created_at?: string
          created_by_user_id?: string | null
          currency_code: string
          customer_id: string
          due_date: string
          id?: string
          issue_date: string
          job_id?: string | null
          number: string
          paid_at?: string | null
          payment_terms_label?: string
          quote_id?: string | null
          scope_of_work?: string
          sent_at?: string | null
          status?: Database["public"]["Enums"]["invoice_status"]
          subtotal?: number
          tax?: number
          title?: string
          total?: number
          updated_at?: string
          viewed_at?: string | null
          voided_at?: string | null
        }
        Update: {
          address_id?: string | null
          amount_paid?: number
          balance?: number
          billing_contact_id?: string | null
          company_id?: string
          created_at?: string
          created_by_user_id?: string | null
          currency_code?: string
          customer_id?: string
          due_date?: string
          id?: string
          issue_date?: string
          job_id?: string | null
          number?: string
          paid_at?: string | null
          payment_terms_label?: string
          quote_id?: string | null
          scope_of_work?: string
          sent_at?: string | null
          status?: Database["public"]["Enums"]["invoice_status"]
          subtotal?: number
          tax?: number
          title?: string
          total?: number
          updated_at?: string
          viewed_at?: string | null
          voided_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "invoices_address_id_fkey"
            columns: ["address_id"]
            isOneToOne: false
            referencedRelation: "addresses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_address_id_fkey"
            columns: ["address_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["address_id"]
          },
          {
            foreignKeyName: "invoices_billing_contact_id_fkey"
            columns: ["billing_contact_id"]
            isOneToOne: false
            referencedRelation: "customer_contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_billing_contact_id_fkey"
            columns: ["billing_contact_id"]
            isOneToOne: false
            referencedRelation: "site_contacts_operational"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_created_by_user_id_fkey"
            columns: ["created_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes_operational"
            referencedColumns: ["id"]
          },
        ]
      }
      job_labour: {
        Row: {
          company_id: string
          created_at: string
          description: string
          hourly_rate: number | null
          id: string
          job_id: string
          minutes: number
          user_id: string
        }
        Insert: {
          company_id: string
          created_at?: string
          description: string
          hourly_rate?: number | null
          id?: string
          job_id: string
          minutes?: number
          user_id: string
        }
        Update: {
          company_id?: string
          created_at?: string
          description?: string
          hourly_rate?: number | null
          id?: string
          job_id?: string
          minutes?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "job_labour_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_labour_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_labour_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      job_notes: {
        Row: {
          body: string
          company_id: string
          created_at: string
          id: string
          job_id: string
          user_id: string
          visibility: Database["public"]["Enums"]["note_visibility"]
        }
        Insert: {
          body: string
          company_id: string
          created_at?: string
          id?: string
          job_id: string
          user_id: string
          visibility?: Database["public"]["Enums"]["note_visibility"]
        }
        Update: {
          body?: string
          company_id?: string
          created_at?: string
          id?: string
          job_id?: string
          user_id?: string
          visibility?: Database["public"]["Enums"]["note_visibility"]
        }
        Relationships: [
          {
            foreignKeyName: "job_notes_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_notes_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_notes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      job_parts: {
        Row: {
          company_id: string
          created_at: string
          description: string
          id: string
          job_id: string
          quantity: number
          recorded_by_user_id: string
          unit_cost: number | null
        }
        Insert: {
          company_id: string
          created_at?: string
          description: string
          id?: string
          job_id: string
          quantity?: number
          recorded_by_user_id: string
          unit_cost?: number | null
        }
        Update: {
          company_id?: string
          created_at?: string
          description?: string
          id?: string
          job_id?: string
          quantity?: number
          recorded_by_user_id?: string
          unit_cost?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "job_parts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_parts_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_parts_recorded_by_user_id_fkey"
            columns: ["recorded_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      job_photos: {
        Row: {
          caption: string | null
          captured_at: string
          company_id: string
          id: string
          job_id: string | null
          kind: Database["public"]["Enums"]["job_photo_kind"]
          storage_reference: string
          thread_id: string | null
          user_id: string
        }
        Insert: {
          caption?: string | null
          captured_at?: string
          company_id: string
          id?: string
          job_id?: string | null
          kind?: Database["public"]["Enums"]["job_photo_kind"]
          storage_reference: string
          thread_id?: string | null
          user_id: string
        }
        Update: {
          caption?: string | null
          captured_at?: string
          company_id?: string
          id?: string
          job_id?: string | null
          kind?: Database["public"]["Enums"]["job_photo_kind"]
          storage_reference?: string
          thread_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "job_photos_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_photos_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_photos_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "office_threads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_photos_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      job_status_history: {
        Row: {
          changed_at: string
          changed_by_user_id: string
          company_id: string
          from_status: Database["public"]["Enums"]["job_status"] | null
          id: string
          job_id: string
          latitude: number | null
          longitude: number | null
          to_status: Database["public"]["Enums"]["job_status"]
        }
        Insert: {
          changed_at?: string
          changed_by_user_id: string
          company_id: string
          from_status?: Database["public"]["Enums"]["job_status"] | null
          id?: string
          job_id: string
          latitude?: number | null
          longitude?: number | null
          to_status: Database["public"]["Enums"]["job_status"]
        }
        Update: {
          changed_at?: string
          changed_by_user_id?: string
          company_id?: string
          from_status?: Database["public"]["Enums"]["job_status"] | null
          id?: string
          job_id?: string
          latitude?: number | null
          longitude?: number | null
          to_status?: Database["public"]["Enums"]["job_status"]
        }
        Relationships: [
          {
            foreignKeyName: "job_status_history_changed_by_user_id_fkey"
            columns: ["changed_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_status_history_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "job_status_history_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      job_transitions: {
        Row: {
          captures_location: boolean
          from_status: Database["public"]["Enums"]["job_status"]
          is_destructive: boolean
          required_permission:
            | Database["public"]["Enums"]["app_permission"]
            | null
          requires_field_work: boolean
          to_status: Database["public"]["Enums"]["job_status"]
        }
        Insert: {
          captures_location?: boolean
          from_status: Database["public"]["Enums"]["job_status"]
          is_destructive?: boolean
          required_permission?:
            | Database["public"]["Enums"]["app_permission"]
            | null
          requires_field_work?: boolean
          to_status: Database["public"]["Enums"]["job_status"]
        }
        Update: {
          captures_location?: boolean
          from_status?: Database["public"]["Enums"]["job_status"]
          is_destructive?: boolean
          required_permission?:
            | Database["public"]["Enums"]["app_permission"]
            | null
          requires_field_work?: boolean
          to_status?: Database["public"]["Enums"]["job_status"]
        }
        Relationships: []
      }
      jobs: {
        Row: {
          actual_end: string | null
          actual_start: string | null
          address_id: string
          company_id: string
          created_at: string
          customer_id: string
          equipment_id: string | null
          generated_for_date: string | null
          id: string
          job_description: string
          kind: Database["public"]["Enums"]["job_kind"]
          number: string
          priority: Database["public"]["Enums"]["job_priority"]
          quote_id: string | null
          scheduled_end: string | null
          scheduled_start: string | null
          service_agreement_id: string | null
          status: Database["public"]["Enums"]["job_status"]
          title: string
          updated_at: string
          vehicle_id: string | null
        }
        Insert: {
          actual_end?: string | null
          actual_start?: string | null
          address_id: string
          company_id: string
          created_at?: string
          customer_id: string
          equipment_id?: string | null
          generated_for_date?: string | null
          id?: string
          job_description?: string
          kind?: Database["public"]["Enums"]["job_kind"]
          number: string
          priority?: Database["public"]["Enums"]["job_priority"]
          quote_id?: string | null
          scheduled_end?: string | null
          scheduled_start?: string | null
          service_agreement_id?: string | null
          status?: Database["public"]["Enums"]["job_status"]
          title?: string
          updated_at?: string
          vehicle_id?: string | null
        }
        Update: {
          actual_end?: string | null
          actual_start?: string | null
          address_id?: string
          company_id?: string
          created_at?: string
          customer_id?: string
          equipment_id?: string | null
          generated_for_date?: string | null
          id?: string
          job_description?: string
          kind?: Database["public"]["Enums"]["job_kind"]
          number?: string
          priority?: Database["public"]["Enums"]["job_priority"]
          quote_id?: string | null
          scheduled_end?: string | null
          scheduled_start?: string | null
          service_agreement_id?: string | null
          status?: Database["public"]["Enums"]["job_status"]
          title?: string
          updated_at?: string
          vehicle_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "jobs_address_id_fkey"
            columns: ["address_id"]
            isOneToOne: false
            referencedRelation: "addresses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_address_id_fkey"
            columns: ["address_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["address_id"]
          },
          {
            foreignKeyName: "jobs_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_equipment_id_fkey"
            columns: ["equipment_id"]
            isOneToOne: false
            referencedRelation: "equipment"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes_operational"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_service_agreement_id_fkey"
            columns: ["service_agreement_id"]
            isOneToOne: false
            referencedRelation: "service_agreements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "jobs_vehicle_id_fkey"
            columns: ["vehicle_id"]
            isOneToOne: false
            referencedRelation: "vehicles"
            referencedColumns: ["id"]
          },
        ]
      }
      member_financial_permissions: {
        Row: {
          can_collect_payments: boolean
          can_invoice: boolean
          company_id: string
          created_at: string
          updated_at: string
          updated_by_user_id: string | null
          user_id: string
        }
        Insert: {
          can_collect_payments?: boolean
          can_invoice?: boolean
          company_id: string
          created_at?: string
          updated_at?: string
          updated_by_user_id?: string | null
          user_id: string
        }
        Update: {
          can_collect_payments?: boolean
          can_invoice?: boolean
          company_id?: string
          created_at?: string
          updated_at?: string
          updated_by_user_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "member_financial_permissions_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_financial_permissions_updated_by_user_id_fkey"
            columns: ["updated_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_financial_permissions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      message_reports: {
        Row: {
          company_id: string
          created_at: string
          details: string | null
          escalated_to_platform: boolean
          id: string
          office_message_id: string | null
          office_thread_id: string | null
          reason: string
          reported_user_id: string | null
          reporter_user_id: string | null
          resolution: string | null
          resolution_note: string | null
          resolved_at: string | null
          resolved_by_user_id: string | null
          sms_conversation_id: string | null
          sms_message_id: string | null
          snapshot_body: string | null
          snapshot_meta: Json
          snapshot_photo_ids: string[]
          snapshot_sent_at: string | null
          source: string
          status: string
        }
        Insert: {
          company_id: string
          created_at?: string
          details?: string | null
          escalated_to_platform?: boolean
          id?: string
          office_message_id?: string | null
          office_thread_id?: string | null
          reason: string
          reported_user_id?: string | null
          reporter_user_id?: string | null
          resolution?: string | null
          resolution_note?: string | null
          resolved_at?: string | null
          resolved_by_user_id?: string | null
          sms_conversation_id?: string | null
          sms_message_id?: string | null
          snapshot_body?: string | null
          snapshot_meta?: Json
          snapshot_photo_ids?: string[]
          snapshot_sent_at?: string | null
          source: string
          status?: string
        }
        Update: {
          company_id?: string
          created_at?: string
          details?: string | null
          escalated_to_platform?: boolean
          id?: string
          office_message_id?: string | null
          office_thread_id?: string | null
          reason?: string
          reported_user_id?: string | null
          reporter_user_id?: string | null
          resolution?: string | null
          resolution_note?: string | null
          resolved_at?: string | null
          resolved_by_user_id?: string | null
          sms_conversation_id?: string | null
          sms_message_id?: string | null
          snapshot_body?: string | null
          snapshot_meta?: Json
          snapshot_photo_ids?: string[]
          snapshot_sent_at?: string | null
          source?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "message_reports_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_reports_office_message_id_fkey"
            columns: ["office_message_id"]
            isOneToOne: false
            referencedRelation: "office_messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_reports_office_thread_id_fkey"
            columns: ["office_thread_id"]
            isOneToOne: false
            referencedRelation: "office_threads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_reports_reported_user_id_fkey"
            columns: ["reported_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_reports_reporter_user_id_fkey"
            columns: ["reporter_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_reports_resolved_by_user_id_fkey"
            columns: ["resolved_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_reports_sms_conversation_id_fkey"
            columns: ["sms_conversation_id"]
            isOneToOne: false
            referencedRelation: "sms_conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_reports_sms_message_id_fkey"
            columns: ["sms_message_id"]
            isOneToOne: false
            referencedRelation: "sms_inbound_messages"
            referencedColumns: ["id"]
          },
        ]
      }
      messaging_provisioning_events: {
        Row: {
          company_id: string
          created_at: string
          error_code: string | null
          error_message: string | null
          id: string
          idempotency_key: string | null
          messaging_account_id: string | null
          operation: string
          outcome: string
          provider_reference: string | null
          stage: string
        }
        Insert: {
          company_id: string
          created_at?: string
          error_code?: string | null
          error_message?: string | null
          id?: string
          idempotency_key?: string | null
          messaging_account_id?: string | null
          operation: string
          outcome: string
          provider_reference?: string | null
          stage: string
        }
        Update: {
          company_id?: string
          created_at?: string
          error_code?: string | null
          error_message?: string | null
          id?: string
          idempotency_key?: string | null
          messaging_account_id?: string | null
          operation?: string
          outcome?: string
          provider_reference?: string | null
          stage?: string
        }
        Relationships: [
          {
            foreignKeyName: "messaging_provisioning_events_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messaging_provisioning_events_messaging_account_id_fkey"
            columns: ["messaging_account_id"]
            isOneToOne: false
            referencedRelation: "company_messaging_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      moderation_actions: {
        Row: {
          action: string
          actor_user_id: string | null
          company_id: string
          created_at: string
          id: string
          note: string | null
          report_id: string | null
          target_user_id: string | null
        }
        Insert: {
          action: string
          actor_user_id?: string | null
          company_id: string
          created_at?: string
          id?: string
          note?: string | null
          report_id?: string | null
          target_user_id?: string | null
        }
        Update: {
          action?: string
          actor_user_id?: string | null
          company_id?: string
          created_at?: string
          id?: string
          note?: string | null
          report_id?: string | null
          target_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "moderation_actions_actor_user_id_fkey"
            columns: ["actor_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "moderation_actions_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "moderation_actions_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: false
            referencedRelation: "message_reports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "moderation_actions_target_user_id_fkey"
            columns: ["target_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      moderation_alerts: {
        Row: {
          attempts: number
          company_id: string | null
          created_at: string
          exhausted_at: string | null
          id: string
          kind: string
          last_error: string | null
          next_attempt_at: string
          note: string | null
          report_id: string | null
          sent_at: string | null
        }
        Insert: {
          attempts?: number
          company_id?: string | null
          created_at?: string
          exhausted_at?: string | null
          id?: string
          kind: string
          last_error?: string | null
          next_attempt_at?: string
          note?: string | null
          report_id?: string | null
          sent_at?: string | null
        }
        Update: {
          attempts?: number
          company_id?: string | null
          created_at?: string
          exhausted_at?: string | null
          id?: string
          kind?: string
          last_error?: string | null
          next_attempt_at?: string
          note?: string | null
          report_id?: string | null
          sent_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "moderation_alerts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "moderation_alerts_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: false
            referencedRelation: "message_reports"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          body: string | null
          channel: Database["public"]["Enums"]["notification_channel"]
          claimed_at: string | null
          company_id: string
          conversation_id: string | null
          created_at: string
          credits_charged: number
          credits_refunded: number
          customer_id: string | null
          deep_link: string | null
          delivered_at: string | null
          encoding: string | null
          failure_reason: string | null
          from_number: string | null
          id: string
          invoice_id: string | null
          job_id: string | null
          messaging_account_id: string | null
          provider_error: string | null
          provider_price_micros: number | null
          provider_reference: string | null
          provider_status: string | null
          push_device_id: string | null
          quote_id: string | null
          recipient: string
          scheduled_message_id: string | null
          segments: number | null
          sent_at: string | null
          sent_by_user_id: string | null
          status: Database["public"]["Enums"]["notification_status"]
          target_user_id: string | null
          template: string
          title: string | null
          to_number: string | null
          twilio_account_sid: string | null
          updated_at: string
        }
        Insert: {
          body?: string | null
          channel: Database["public"]["Enums"]["notification_channel"]
          claimed_at?: string | null
          company_id: string
          conversation_id?: string | null
          created_at?: string
          credits_charged?: number
          credits_refunded?: number
          customer_id?: string | null
          deep_link?: string | null
          delivered_at?: string | null
          encoding?: string | null
          failure_reason?: string | null
          from_number?: string | null
          id?: string
          invoice_id?: string | null
          job_id?: string | null
          messaging_account_id?: string | null
          provider_error?: string | null
          provider_price_micros?: number | null
          provider_reference?: string | null
          provider_status?: string | null
          push_device_id?: string | null
          quote_id?: string | null
          recipient?: string
          scheduled_message_id?: string | null
          segments?: number | null
          sent_at?: string | null
          sent_by_user_id?: string | null
          status?: Database["public"]["Enums"]["notification_status"]
          target_user_id?: string | null
          template?: string
          title?: string | null
          to_number?: string | null
          twilio_account_sid?: string | null
          updated_at?: string
        }
        Update: {
          body?: string | null
          channel?: Database["public"]["Enums"]["notification_channel"]
          claimed_at?: string | null
          company_id?: string
          conversation_id?: string | null
          created_at?: string
          credits_charged?: number
          credits_refunded?: number
          customer_id?: string | null
          deep_link?: string | null
          delivered_at?: string | null
          encoding?: string | null
          failure_reason?: string | null
          from_number?: string | null
          id?: string
          invoice_id?: string | null
          job_id?: string | null
          messaging_account_id?: string | null
          provider_error?: string | null
          provider_price_micros?: number | null
          provider_reference?: string | null
          provider_status?: string | null
          push_device_id?: string | null
          quote_id?: string | null
          recipient?: string
          scheduled_message_id?: string | null
          segments?: number | null
          sent_at?: string | null
          sent_by_user_id?: string | null
          status?: Database["public"]["Enums"]["notification_status"]
          target_user_id?: string | null
          template?: string
          title?: string | null
          to_number?: string | null
          twilio_account_sid?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "sms_conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_messaging_account_id_fkey"
            columns: ["messaging_account_id"]
            isOneToOne: false
            referencedRelation: "company_messaging_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_push_device_id_fkey"
            columns: ["push_device_id"]
            isOneToOne: false
            referencedRelation: "push_devices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes_operational"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_scheduled_message_id_fkey"
            columns: ["scheduled_message_id"]
            isOneToOne: false
            referencedRelation: "scheduled_messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_sent_by_user_id_fkey"
            columns: ["sent_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_target_user_id_fkey"
            columns: ["target_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      office_messages: {
        Row: {
          body: string
          company_id: string
          created_at: string
          id: string
          job_photo_ids: string[]
          sender_user_id: string
          thread_id: string
        }
        Insert: {
          body: string
          company_id: string
          created_at?: string
          id?: string
          job_photo_ids?: string[]
          sender_user_id: string
          thread_id: string
        }
        Update: {
          body?: string
          company_id?: string
          created_at?: string
          id?: string
          job_photo_ids?: string[]
          sender_user_id?: string
          thread_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "office_messages_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "office_messages_sender_user_id_fkey"
            columns: ["sender_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "office_messages_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "office_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      office_thread_reads: {
        Row: {
          company_id: string
          last_read_at: string
          thread_id: string
          user_id: string
        }
        Insert: {
          company_id: string
          last_read_at?: string
          thread_id: string
          user_id: string
        }
        Update: {
          company_id?: string
          last_read_at?: string
          thread_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "office_thread_reads_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "office_thread_reads_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "office_threads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "office_thread_reads_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      office_threads: {
        Row: {
          company_id: string
          created_at: string
          created_by_user_id: string
          customer_id: string | null
          engineer_user_id: string
          id: string
          job_id: string | null
          last_message_at: string
          last_message_preview: string
          last_sender_user_id: string | null
          subject: string
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by_user_id: string
          customer_id?: string | null
          engineer_user_id: string
          id?: string
          job_id?: string | null
          last_message_at?: string
          last_message_preview?: string
          last_sender_user_id?: string | null
          subject?: string
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by_user_id?: string
          customer_id?: string | null
          engineer_user_id?: string
          id?: string
          job_id?: string | null
          last_message_at?: string
          last_message_preview?: string
          last_sender_user_id?: string | null
          subject?: string
        }
        Relationships: [
          {
            foreignKeyName: "office_threads_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "office_threads_created_by_user_id_fkey"
            columns: ["created_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "office_threads_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "office_threads_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "office_threads_engineer_user_id_fkey"
            columns: ["engineer_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "office_threads_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "office_threads_last_sender_user_id_fkey"
            columns: ["last_sender_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_intents: {
        Row: {
          amount_cents: number
          application_fee_cents: number
          client_secret_issued_at: string | null
          company_id: string
          created_at: string
          currency_code: string
          id: string
          invoice_id: string
          status: string
          stripe_account_id: string
          stripe_payment_intent_id: string
          updated_at: string
        }
        Insert: {
          amount_cents: number
          application_fee_cents?: number
          client_secret_issued_at?: string | null
          company_id: string
          created_at?: string
          currency_code?: string
          id?: string
          invoice_id: string
          status?: string
          stripe_account_id: string
          stripe_payment_intent_id: string
          updated_at?: string
        }
        Update: {
          amount_cents?: number
          application_fee_cents?: number
          client_secret_issued_at?: string | null
          company_id?: string
          created_at?: string
          currency_code?: string
          id?: string
          invoice_id?: string
          status?: string
          stripe_account_id?: string
          stripe_payment_intent_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_intents_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_intents_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      payments: {
        Row: {
          amount: number
          application_fee_cents: number | null
          company_id: string
          created_at: string
          currency_code: string | null
          failure_reason: string | null
          id: string
          invoice_id: string
          is_simulated: boolean
          method: Database["public"]["Enums"]["payment_method"]
          net_cents: number | null
          note: string | null
          paid_by_customer: boolean
          processing_fee_cents: number | null
          received_at: string
          recorded_by_user_id: string | null
          reference: string | null
          status: Database["public"]["Enums"]["payment_status"]
          stripe_account_id: string | null
          stripe_charge_id: string | null
          stripe_payment_intent_id: string | null
        }
        Insert: {
          amount: number
          application_fee_cents?: number | null
          company_id: string
          created_at?: string
          currency_code?: string | null
          failure_reason?: string | null
          id?: string
          invoice_id: string
          is_simulated?: boolean
          method: Database["public"]["Enums"]["payment_method"]
          net_cents?: number | null
          note?: string | null
          paid_by_customer?: boolean
          processing_fee_cents?: number | null
          received_at?: string
          recorded_by_user_id?: string | null
          reference?: string | null
          status?: Database["public"]["Enums"]["payment_status"]
          stripe_account_id?: string | null
          stripe_charge_id?: string | null
          stripe_payment_intent_id?: string | null
        }
        Update: {
          amount?: number
          application_fee_cents?: number | null
          company_id?: string
          created_at?: string
          currency_code?: string | null
          failure_reason?: string | null
          id?: string
          invoice_id?: string
          is_simulated?: boolean
          method?: Database["public"]["Enums"]["payment_method"]
          net_cents?: number | null
          note?: string | null
          paid_by_customer?: boolean
          processing_fee_cents?: number | null
          received_at?: string
          recorded_by_user_id?: string | null
          reference?: string | null
          status?: Database["public"]["Enums"]["payment_status"]
          stripe_account_id?: string | null
          stripe_charge_id?: string | null
          stripe_payment_intent_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "payments_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_recorded_by_user_id_fkey"
            columns: ["recorded_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      permission_matrix_contract: {
        Row: {
          fingerprint: string
          grant_count: number
          id: boolean
          permission_count: number
          synced_at: string
        }
        Insert: {
          fingerprint: string
          grant_count: number
          id?: boolean
          permission_count: number
          synced_at?: string
        }
        Update: {
          fingerprint?: string
          grant_count?: number
          id?: boolean
          permission_count?: number
          synced_at?: string
        }
        Relationships: []
      }
      platform_settings: {
        Row: {
          description: string
          key: string
          updated_at: string
          value: Json
        }
        Insert: {
          description?: string
          key: string
          updated_at?: string
          value: Json
        }
        Update: {
          description?: string
          key?: string
          updated_at?: string
          value?: Json
        }
        Relationships: []
      }
      push_devices: {
        Row: {
          app_version: string
          bundle_id: string
          company_id: string
          created_at: string
          device_model: string
          environment: string
          id: string
          last_registered_at: string
          platform: string
          revoked_at: string | null
          revoked_reason: string | null
          token: string
          updated_at: string
          user_id: string
        }
        Insert: {
          app_version?: string
          bundle_id?: string
          company_id: string
          created_at?: string
          device_model?: string
          environment?: string
          id?: string
          last_registered_at?: string
          platform?: string
          revoked_at?: string | null
          revoked_reason?: string | null
          token: string
          updated_at?: string
          user_id: string
        }
        Update: {
          app_version?: string
          bundle_id?: string
          company_id?: string
          created_at?: string
          device_model?: string
          environment?: string
          id?: string
          last_registered_at?: string
          platform?: string
          revoked_at?: string | null
          revoked_reason?: string | null
          token?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "push_devices_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "push_devices_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      quote_line_items: {
        Row: {
          company_id: string
          id: string
          item_description: string
          line_total: number
          quantity: number
          quote_id: string
          sort_order: number
          tax_rate: number
          unit_price: number
        }
        Insert: {
          company_id: string
          id?: string
          item_description?: string
          line_total?: number
          quantity?: number
          quote_id: string
          sort_order?: number
          tax_rate?: number
          unit_price?: number
        }
        Update: {
          company_id?: string
          id?: string
          item_description?: string
          line_total?: number
          quantity?: number
          quote_id?: string
          sort_order?: number
          tax_rate?: number
          unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: "quote_line_items_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_line_items_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_line_items_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes_operational"
            referencedColumns: ["id"]
          },
        ]
      }
      quote_share_tokens: {
        Row: {
          company_id: string
          created_at: string
          created_by_user_id: string | null
          id: string
          last_viewed_at: string | null
          quote_id: string
          revoked_at: string | null
          token: string
          view_count: number
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by_user_id?: string | null
          id?: string
          last_viewed_at?: string | null
          quote_id: string
          revoked_at?: string | null
          token: string
          view_count?: number
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by_user_id?: string | null
          id?: string
          last_viewed_at?: string | null
          quote_id?: string
          revoked_at?: string | null
          token?: string
          view_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "quote_share_tokens_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_share_tokens_created_by_user_id_fkey"
            columns: ["created_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_share_tokens_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quote_share_tokens_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes_operational"
            referencedColumns: ["id"]
          },
        ]
      }
      quotes: {
        Row: {
          accepted_at: string | null
          address_id: string
          company_id: string
          converted_job_id: string | null
          created_at: string
          customer_id: string
          declined_at: string | null
          id: string
          number: string
          scope_of_work: string
          sent_at: string | null
          status: Database["public"]["Enums"]["quote_status"]
          subtotal: number
          tax: number
          title: string
          total: number
          updated_at: string
          valid_until: string | null
          viewed_at: string | null
        }
        Insert: {
          accepted_at?: string | null
          address_id: string
          company_id: string
          converted_job_id?: string | null
          created_at?: string
          customer_id: string
          declined_at?: string | null
          id?: string
          number: string
          scope_of_work?: string
          sent_at?: string | null
          status?: Database["public"]["Enums"]["quote_status"]
          subtotal?: number
          tax?: number
          title?: string
          total?: number
          updated_at?: string
          valid_until?: string | null
          viewed_at?: string | null
        }
        Update: {
          accepted_at?: string | null
          address_id?: string
          company_id?: string
          converted_job_id?: string | null
          created_at?: string
          customer_id?: string
          declined_at?: string | null
          id?: string
          number?: string
          scope_of_work?: string
          sent_at?: string | null
          status?: Database["public"]["Enums"]["quote_status"]
          subtotal?: number
          tax?: number
          title?: string
          total?: number
          updated_at?: string
          valid_until?: string | null
          viewed_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "quotes_address_id_fkey"
            columns: ["address_id"]
            isOneToOne: false
            referencedRelation: "addresses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_address_id_fkey"
            columns: ["address_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["address_id"]
          },
          {
            foreignKeyName: "quotes_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_converted_job_id_fkey"
            columns: ["converted_job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
        ]
      }
      role_permissions: {
        Row: {
          permission: Database["public"]["Enums"]["app_permission"]
          role: Database["public"]["Enums"]["app_role"]
        }
        Insert: {
          permission: Database["public"]["Enums"]["app_permission"]
          role: Database["public"]["Enums"]["app_role"]
        }
        Update: {
          permission?: Database["public"]["Enums"]["app_permission"]
          role?: Database["public"]["Enums"]["app_role"]
        }
        Relationships: []
      }
      scheduled_messages: {
        Row: {
          attempts: number
          body: string | null
          cancelled_at: string | null
          cancelled_by_user_id: string | null
          claimed_at: string | null
          company_id: string
          created_at: string
          created_by_user_id: string | null
          customer_id: string
          dedupe_key: string | null
          eta_text: string | null
          failure_reason: string | null
          id: string
          invoice_id: string | null
          job_id: string | null
          notification_id: string | null
          quote_id: string | null
          scheduled_for: string
          sent_at: string | null
          source: string
          status: string
          template_key: string
          to_number: string | null
          updated_at: string
        }
        Insert: {
          attempts?: number
          body?: string | null
          cancelled_at?: string | null
          cancelled_by_user_id?: string | null
          claimed_at?: string | null
          company_id: string
          created_at?: string
          created_by_user_id?: string | null
          customer_id: string
          dedupe_key?: string | null
          eta_text?: string | null
          failure_reason?: string | null
          id?: string
          invoice_id?: string | null
          job_id?: string | null
          notification_id?: string | null
          quote_id?: string | null
          scheduled_for: string
          sent_at?: string | null
          source: string
          status?: string
          template_key: string
          to_number?: string | null
          updated_at?: string
        }
        Update: {
          attempts?: number
          body?: string | null
          cancelled_at?: string | null
          cancelled_by_user_id?: string | null
          claimed_at?: string | null
          company_id?: string
          created_at?: string
          created_by_user_id?: string | null
          customer_id?: string
          dedupe_key?: string | null
          eta_text?: string | null
          failure_reason?: string | null
          id?: string
          invoice_id?: string | null
          job_id?: string | null
          notification_id?: string | null
          quote_id?: string | null
          scheduled_for?: string
          sent_at?: string | null
          source?: string
          status?: string
          template_key?: string
          to_number?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "scheduled_messages_cancelled_by_user_id_fkey"
            columns: ["cancelled_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scheduled_messages_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scheduled_messages_created_by_user_id_fkey"
            columns: ["created_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scheduled_messages_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scheduled_messages_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scheduled_messages_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scheduled_messages_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scheduled_messages_notification_id_fkey"
            columns: ["notification_id"]
            isOneToOne: false
            referencedRelation: "notifications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scheduled_messages_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scheduled_messages_quote_id_fkey"
            columns: ["quote_id"]
            isOneToOne: false
            referencedRelation: "quotes_operational"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scheduled_messages_template_key_fkey"
            columns: ["template_key"]
            isOneToOne: false
            referencedRelation: "sms_template_defaults"
            referencedColumns: ["template_key"]
          },
        ]
      }
      service_agreements: {
        Row: {
          address_id: string
          company_id: string
          created_at: string
          customer_id: string
          equipment_id: string | null
          frequency: Database["public"]["Enums"]["service_frequency"]
          id: string
          interval_days: number | null
          is_active: boolean
          last_generated_job_id: string | null
          last_generated_on: string | null
          lead_time_days: number
          next_due_date: string
          notes: string | null
          template_description: string
          template_job_kind: Database["public"]["Enums"]["job_kind"]
          template_title: string
          updated_at: string
        }
        Insert: {
          address_id: string
          company_id: string
          created_at?: string
          customer_id: string
          equipment_id?: string | null
          frequency: Database["public"]["Enums"]["service_frequency"]
          id?: string
          interval_days?: number | null
          is_active?: boolean
          last_generated_job_id?: string | null
          last_generated_on?: string | null
          lead_time_days?: number
          next_due_date: string
          notes?: string | null
          template_description?: string
          template_job_kind: Database["public"]["Enums"]["job_kind"]
          template_title?: string
          updated_at?: string
        }
        Update: {
          address_id?: string
          company_id?: string
          created_at?: string
          customer_id?: string
          equipment_id?: string | null
          frequency?: Database["public"]["Enums"]["service_frequency"]
          id?: string
          interval_days?: number | null
          is_active?: boolean
          last_generated_job_id?: string | null
          last_generated_on?: string | null
          lead_time_days?: number
          next_due_date?: string
          notes?: string | null
          template_description?: string
          template_job_kind?: Database["public"]["Enums"]["job_kind"]
          template_title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "service_agreements_address_id_fkey"
            columns: ["address_id"]
            isOneToOne: false
            referencedRelation: "addresses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_agreements_address_id_fkey"
            columns: ["address_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["address_id"]
          },
          {
            foreignKeyName: "service_agreements_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_agreements_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_agreements_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_agreements_equipment_id_fkey"
            columns: ["equipment_id"]
            isOneToOne: false
            referencedRelation: "equipment"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "service_agreements_last_generated_job_id_fkey"
            columns: ["last_generated_job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      sms_automation_settings: {
        Row: {
          company_id: string
          enabled: boolean
          template_key: string
          updated_at: string
          updated_by_user_id: string | null
        }
        Insert: {
          company_id: string
          enabled: boolean
          template_key: string
          updated_at?: string
          updated_by_user_id?: string | null
        }
        Update: {
          company_id?: string
          enabled?: boolean
          template_key?: string
          updated_at?: string
          updated_by_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sms_automation_settings_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_automation_settings_template_key_fkey"
            columns: ["template_key"]
            isOneToOne: false
            referencedRelation: "sms_template_defaults"
            referencedColumns: ["template_key"]
          },
          {
            foreignKeyName: "sms_automation_settings_updated_by_user_id_fkey"
            columns: ["updated_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      sms_bundles: {
        Row: {
          credits: number
          id: string
          is_active: boolean
          price_cents: number
          sort_order: number
          updated_at: string
        }
        Insert: {
          credits: number
          id: string
          is_active?: boolean
          price_cents: number
          sort_order?: number
          updated_at?: string
        }
        Update: {
          credits?: number
          id?: string
          is_active?: boolean
          price_cents?: number
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
      sms_conversation_reads: {
        Row: {
          company_id: string
          conversation_id: string
          last_read_at: string
          user_id: string
        }
        Insert: {
          company_id: string
          conversation_id: string
          last_read_at?: string
          user_id: string
        }
        Update: {
          company_id?: string
          conversation_id?: string
          last_read_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sms_conversation_reads_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_conversation_reads_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "sms_conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_conversation_reads_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      sms_conversations: {
        Row: {
          company_id: string
          contact_id: string | null
          created_at: string
          customer_id: string | null
          id: string
          last_direction: string
          last_job_id: string | null
          last_message_at: string
          last_preview: string
          phone_e164: string
        }
        Insert: {
          company_id: string
          contact_id?: string | null
          created_at?: string
          customer_id?: string | null
          id?: string
          last_direction?: string
          last_job_id?: string | null
          last_message_at?: string
          last_preview?: string
          phone_e164: string
        }
        Update: {
          company_id?: string
          contact_id?: string | null
          created_at?: string
          customer_id?: string | null
          id?: string
          last_direction?: string
          last_job_id?: string | null
          last_message_at?: string
          last_preview?: string
          phone_e164?: string
        }
        Relationships: [
          {
            foreignKeyName: "sms_conversations_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_conversations_contact_id_fkey"
            columns: ["contact_id"]
            isOneToOne: false
            referencedRelation: "customer_contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_conversations_contact_id_fkey"
            columns: ["contact_id"]
            isOneToOne: false
            referencedRelation: "site_contacts_operational"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_conversations_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_conversations_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_conversations_last_job_id_fkey"
            columns: ["last_job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      sms_credit_ledger: {
        Row: {
          amount: number
          balance_after: number
          company_id: string
          created_at: string
          customer_id: string | null
          id: string
          job_id: string | null
          notification_id: string | null
          purchase_reference: string | null
          transaction_type: Database["public"]["Enums"]["sms_ledger_transaction_type"]
        }
        Insert: {
          amount: number
          balance_after: number
          company_id: string
          created_at?: string
          customer_id?: string | null
          id?: string
          job_id?: string | null
          notification_id?: string | null
          purchase_reference?: string | null
          transaction_type: Database["public"]["Enums"]["sms_ledger_transaction_type"]
        }
        Update: {
          amount?: number
          balance_after?: number
          company_id?: string
          created_at?: string
          customer_id?: string | null
          id?: string
          job_id?: string | null
          notification_id?: string | null
          purchase_reference?: string | null
          transaction_type?: Database["public"]["Enums"]["sms_ledger_transaction_type"]
        }
        Relationships: [
          {
            foreignKeyName: "sms_credit_ledger_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_credit_ledger_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_credit_ledger_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_credit_ledger_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_credit_ledger_notification_id_fkey"
            columns: ["notification_id"]
            isOneToOne: false
            referencedRelation: "notifications"
            referencedColumns: ["id"]
          },
        ]
      }
      sms_credit_purchases: {
        Row: {
          bundle_id: string | null
          company_id: string
          created_at: string
          credited_at: string | null
          credits: number
          currency_code: string
          id: string
          price_cents: number
          requested_by_user_id: string | null
          status: string
          stripe_checkout_session_id: string | null
          stripe_payment_intent_id: string | null
          updated_at: string
        }
        Insert: {
          bundle_id?: string | null
          company_id: string
          created_at?: string
          credited_at?: string | null
          credits: number
          currency_code?: string
          id?: string
          price_cents: number
          requested_by_user_id?: string | null
          status?: string
          stripe_checkout_session_id?: string | null
          stripe_payment_intent_id?: string | null
          updated_at?: string
        }
        Update: {
          bundle_id?: string | null
          company_id?: string
          created_at?: string
          credited_at?: string | null
          credits?: number
          currency_code?: string
          id?: string
          price_cents?: number
          requested_by_user_id?: string | null
          status?: string
          stripe_checkout_session_id?: string | null
          stripe_payment_intent_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "sms_credit_purchases_bundle_id_fkey"
            columns: ["bundle_id"]
            isOneToOne: false
            referencedRelation: "sms_bundles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_credit_purchases_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_credit_purchases_requested_by_user_id_fkey"
            columns: ["requested_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      sms_inbound_messages: {
        Row: {
          body: string
          company_id: string
          conversation_id: string
          customer_id: string | null
          from_number: string
          id: string
          job_id: string | null
          keyword_type: string | null
          messaging_account_id: string
          provider_reference: string
          received_at: string
          to_number: string
        }
        Insert: {
          body?: string
          company_id: string
          conversation_id: string
          customer_id?: string | null
          from_number: string
          id?: string
          job_id?: string | null
          keyword_type?: string | null
          messaging_account_id: string
          provider_reference: string
          received_at?: string
          to_number: string
        }
        Update: {
          body?: string
          company_id?: string
          conversation_id?: string
          customer_id?: string | null
          from_number?: string
          id?: string
          job_id?: string | null
          keyword_type?: string | null
          messaging_account_id?: string
          provider_reference?: string
          received_at?: string
          to_number?: string
        }
        Relationships: [
          {
            foreignKeyName: "sms_inbound_messages_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_inbound_messages_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "sms_conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_inbound_messages_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_inbound_messages_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_inbound_messages_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_inbound_messages_messaging_account_id_fkey"
            columns: ["messaging_account_id"]
            isOneToOne: false
            referencedRelation: "company_messaging_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      sms_opt_outs: {
        Row: {
          company_id: string
          contact_id: string | null
          customer_id: string | null
          id: string
          keyword: string | null
          last_message_sid: string | null
          messaging_service_sid: string | null
          opted_in_at: string | null
          opted_out: boolean
          opted_out_at: string | null
          phone_e164: string
          source: string
          twilio_account_sid: string | null
          updated_at: string
        }
        Insert: {
          company_id: string
          contact_id?: string | null
          customer_id?: string | null
          id?: string
          keyword?: string | null
          last_message_sid?: string | null
          messaging_service_sid?: string | null
          opted_in_at?: string | null
          opted_out?: boolean
          opted_out_at?: string | null
          phone_e164: string
          source: string
          twilio_account_sid?: string | null
          updated_at?: string
        }
        Update: {
          company_id?: string
          contact_id?: string | null
          customer_id?: string | null
          id?: string
          keyword?: string | null
          last_message_sid?: string | null
          messaging_service_sid?: string | null
          opted_in_at?: string | null
          opted_out?: boolean
          opted_out_at?: string | null
          phone_e164?: string
          source?: string
          twilio_account_sid?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "sms_opt_outs_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_opt_outs_contact_id_fkey"
            columns: ["contact_id"]
            isOneToOne: false
            referencedRelation: "customer_contacts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_opt_outs_contact_id_fkey"
            columns: ["contact_id"]
            isOneToOne: false
            referencedRelation: "site_contacts_operational"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_opt_outs_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_opt_outs_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
        ]
      }
      sms_template_defaults: {
        Row: {
          allowed_variables: string[]
          automation_default: boolean
          automation_description: string | null
          body: string
          category: string
          context: string
          is_automatable: boolean
          sort_order: number
          template_key: string
          title: string
        }
        Insert: {
          allowed_variables: string[]
          automation_default?: boolean
          automation_description?: string | null
          body: string
          category: string
          context: string
          is_automatable?: boolean
          sort_order: number
          template_key: string
          title: string
        }
        Update: {
          allowed_variables?: string[]
          automation_default?: boolean
          automation_description?: string | null
          body?: string
          category?: string
          context?: string
          is_automatable?: boolean
          sort_order?: number
          template_key?: string
          title?: string
        }
        Relationships: []
      }
      sms_templates: {
        Row: {
          body: string
          company_id: string
          template_key: string
          updated_at: string
          updated_by_user_id: string | null
        }
        Insert: {
          body: string
          company_id: string
          template_key: string
          updated_at?: string
          updated_by_user_id?: string | null
        }
        Update: {
          body?: string
          company_id?: string
          template_key?: string
          updated_at?: string
          updated_by_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sms_templates_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sms_templates_template_key_fkey"
            columns: ["template_key"]
            isOneToOne: false
            referencedRelation: "sms_template_defaults"
            referencedColumns: ["template_key"]
          },
          {
            foreignKeyName: "sms_templates_updated_by_user_id_fkey"
            columns: ["updated_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      stripe_connect_accounts: {
        Row: {
          charges_enabled: boolean
          company_id: string
          country_code: string
          created_at: string
          default_currency: string
          details_submitted: boolean
          disabled_reason: string | null
          last_synced_at: string
          onboarded_at: string | null
          payouts_enabled: boolean
          requirements_due: string[]
          stripe_account_id: string
          updated_at: string
        }
        Insert: {
          charges_enabled?: boolean
          company_id: string
          country_code?: string
          created_at?: string
          default_currency?: string
          details_submitted?: boolean
          disabled_reason?: string | null
          last_synced_at?: string
          onboarded_at?: string | null
          payouts_enabled?: boolean
          requirements_due?: string[]
          stripe_account_id: string
          updated_at?: string
        }
        Update: {
          charges_enabled?: boolean
          company_id?: string
          country_code?: string
          created_at?: string
          default_currency?: string
          details_submitted?: boolean
          disabled_reason?: string | null
          last_synced_at?: string
          onboarded_at?: string | null
          payouts_enabled?: boolean
          requirements_due?: string[]
          stripe_account_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "stripe_connect_accounts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: true
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      stripe_events: {
        Row: {
          account_id: string | null
          company_id: string | null
          error_detail: string | null
          id: string
          livemode: boolean
          outcome: string | null
          processed_at: string | null
          received_at: string
          type: string
        }
        Insert: {
          account_id?: string | null
          company_id?: string | null
          error_detail?: string | null
          id: string
          livemode?: boolean
          outcome?: string | null
          processed_at?: string | null
          received_at?: string
          type: string
        }
        Update: {
          account_id?: string | null
          company_id?: string | null
          error_detail?: string | null
          id?: string
          livemode?: boolean
          outcome?: string | null
          processed_at?: string | null
          received_at?: string
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "stripe_events_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      subscription_tiers: {
        Row: {
          additional_user_cents: number
          annual_cents: number | null
          apple_product_annual: string | null
          apple_product_monthly: string | null
          base_cents: number
          display_name: string
          id: string
          included_users: number | null
          is_active: boolean
          max_users: number
          min_users: number
          sort_order: number
          tagline: string
          updated_at: string
          user_limit: number | null
        }
        Insert: {
          additional_user_cents: number
          annual_cents?: number | null
          apple_product_annual?: string | null
          apple_product_monthly?: string | null
          base_cents: number
          display_name: string
          id: string
          included_users?: number | null
          is_active?: boolean
          max_users: number
          min_users: number
          sort_order?: number
          tagline?: string
          updated_at?: string
          user_limit?: number | null
        }
        Update: {
          additional_user_cents?: number
          annual_cents?: number | null
          apple_product_annual?: string | null
          apple_product_monthly?: string | null
          base_cents?: number
          display_name?: string
          id?: string
          included_users?: number | null
          is_active?: boolean
          max_users?: number
          min_users?: number
          sort_order?: number
          tagline?: string
          updated_at?: string
          user_limit?: number | null
        }
        Relationships: []
      }
      vehicles: {
        Row: {
          company_id: string
          created_at: string
          created_by_user_id: string | null
          customer_id: string
          id: string
          make: string
          model: string
          registration: string
          updated_at: string
          vin: string
        }
        Insert: {
          company_id: string
          created_at?: string
          created_by_user_id?: string | null
          customer_id: string
          id?: string
          make?: string
          model?: string
          registration?: string
          updated_at?: string
          vin?: string
        }
        Update: {
          company_id?: string
          created_at?: string
          created_by_user_id?: string | null
          customer_id?: string
          id?: string
          make?: string
          model?: string
          registration?: string
          updated_at?: string
          vin?: string
        }
        Relationships: [
          {
            foreignKeyName: "vehicles_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vehicles_created_by_user_id_fkey"
            columns: ["created_by_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vehicles_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "vehicles_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      assigned_site_customers: {
        Row: {
          access_notes: string | null
          address_id: string | null
          city: string | null
          company_id: string | null
          id: string | null
          latitude: number | null
          line1: string | null
          line2: string | null
          longitude: number | null
          name: string | null
          postal_code: string | null
          state: string | null
          type: Database["public"]["Enums"]["customer_type"] | null
        }
        Relationships: [
          {
            foreignKeyName: "customers_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
        ]
      }
      moderation_alerts_attention: {
        Row: {
          alert_id: string | null
          attempts: number | null
          company_name: string | null
          created_at: string | null
          escalated: boolean | null
          exhausted_at: string | null
          kind: string | null
          last_error: string | null
          reason: string | null
          report_id: string | null
          report_status: string | null
        }
        Relationships: [
          {
            foreignKeyName: "moderation_alerts_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: false
            referencedRelation: "message_reports"
            referencedColumns: ["id"]
          },
        ]
      }
      quotes_operational: {
        Row: {
          accepted_at: string | null
          address_id: string | null
          company_id: string | null
          converted_job_id: string | null
          created_at: string | null
          customer_id: string | null
          declined_at: string | null
          id: string | null
          number: string | null
          scope_of_work: string | null
          sent_at: string | null
          status: Database["public"]["Enums"]["quote_status"] | null
          title: string | null
          valid_until: string | null
          viewed_at: string | null
        }
        Insert: {
          accepted_at?: string | null
          address_id?: string | null
          company_id?: string | null
          converted_job_id?: string | null
          created_at?: string | null
          customer_id?: string | null
          declined_at?: string | null
          id?: string | null
          number?: string | null
          scope_of_work?: string | null
          sent_at?: string | null
          status?: Database["public"]["Enums"]["quote_status"] | null
          title?: string | null
          valid_until?: string | null
          viewed_at?: string | null
        }
        Update: {
          accepted_at?: string | null
          address_id?: string | null
          company_id?: string | null
          converted_job_id?: string | null
          created_at?: string | null
          customer_id?: string | null
          declined_at?: string | null
          id?: string | null
          number?: string | null
          scope_of_work?: string | null
          sent_at?: string | null
          status?: Database["public"]["Enums"]["quote_status"] | null
          title?: string | null
          valid_until?: string | null
          viewed_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "quotes_address_id_fkey"
            columns: ["address_id"]
            isOneToOne: false
            referencedRelation: "addresses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_address_id_fkey"
            columns: ["address_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["address_id"]
          },
          {
            foreignKeyName: "quotes_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_converted_job_id_fkey"
            columns: ["converted_job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quotes_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
        ]
      }
      site_contacts_operational: {
        Row: {
          company_id: string | null
          contact_role: string | null
          customer_id: string | null
          id: string | null
          name: string | null
          phone: string | null
        }
        Insert: {
          company_id?: string | null
          contact_role?: string | null
          customer_id?: string | null
          id?: string | null
          name?: string | null
          phone?: string | null
        }
        Update: {
          company_id?: string | null
          contact_role?: string | null
          customer_id?: string | null
          id?: string | null
          name?: string | null
          phone?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "customer_contacts_company_id_fkey"
            columns: ["company_id"]
            isOneToOne: false
            referencedRelation: "companies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_contacts_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "assigned_site_customers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "customer_contacts_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "customers"
            referencedColumns: ["id"]
          },
        ]
      }
      sms_thread_messages: {
        Row: {
          at: string | null
          body: string | null
          company_id: string | null
          conversation_id: string | null
          credits_charged: number | null
          credits_refunded: number | null
          customer_id: string | null
          direction: string | null
          failure_reason: string | null
          id: string | null
          invoice_id: string | null
          job_id: string | null
          quote_id: string | null
          segments: number | null
          sent_by_user_id: string | null
          status: string | null
          template: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      accept_invitation: { Args: { p_token: string }; Returns: string }
      account_deletion_context: {
        Args: never
        Returns: {
          company_name: string
          has_membership: boolean
          is_owner: boolean
          is_sole_owner: boolean
          other_active_members: number
        }[]
      }
      adopt_harbour_south_payments: {
        Args: { p_company: string }
        Returns: boolean
      }
      apple_apply_transaction: {
        Args: {
          p_company: string
          p_renewal?: Json
          p_source?: string
          p_transaction: Json
        }
        Returns: string
      }
      apple_ms: { Args: { p: string }; Returns: string }
      apply_job_status: {
        Args: {
          p_job: string
          p_latitude?: number
          p_longitude?: number
          p_to: Database["public"]["Enums"]["job_status"]
        }
        Returns: undefined
      }
      apply_tenant_rls: {
        Args: { p_read_perm?: string; p_table: string; p_write_perm?: string }
        Returns: undefined
      }
      assign_job: {
        Args: {
          p_acknowledges_conflict?: boolean
          p_job: string
          p_worker?: string
        }
        Returns: undefined
      }
      block_chat_user: {
        Args: { p_details?: string; p_reason?: string; p_user: string }
        Returns: string
      }
      cancel_scheduled_sms: { Args: { p_id: string }; Returns: boolean }
      chat_content_violation: { Args: { p_text: string }; Returns: string }
      chat_normalize: { Args: { p_text: string }; Returns: string }
      chat_user_is_restricted: { Args: { p_user: string }; Returns: boolean }
      claim_due_scheduled_sms: {
        Args: { p_limit?: number }
        Returns: {
          attempts: number
          body: string | null
          cancelled_at: string | null
          cancelled_by_user_id: string | null
          claimed_at: string | null
          company_id: string
          created_at: string
          created_by_user_id: string | null
          customer_id: string
          dedupe_key: string | null
          eta_text: string | null
          failure_reason: string | null
          id: string
          invoice_id: string | null
          job_id: string | null
          notification_id: string | null
          quote_id: string | null
          scheduled_for: string
          sent_at: string | null
          source: string
          status: string
          template_key: string
          to_number: string | null
          updated_at: string
        }[]
        SetofOptions: {
          from: "*"
          to: "scheduled_messages"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      claim_push_batch: {
        Args: { p_limit?: number }
        Returns: {
          body: string
          bundle_id: string
          company_id: string
          deep_link: string
          environment: string
          event: string
          job_id: string
          notification_id: string
          title: string
          token: string
        }[]
      }
      commerce_company_scope: { Args: { p_company?: string }; Returns: string }
      communications_unread: {
        Args: never
        Returns: {
          customer_unread: number
          latest_at: string
          latest_body: string
          latest_link: string
          latest_title: string
          office_unread: number
        }[]
      }
      company_active_paid_users: {
        Args: { p_company?: string }
        Returns: number
      }
      company_active_paid_users_for: {
        Args: { p_company: string }
        Returns: number
      }
      company_can_accept_payments: {
        Args: { p_company?: string }
        Returns: boolean
      }
      company_commercial_state: {
        Args: { p_company?: string }
        Returns: {
          active_users: number
          apple_environment: string
          apple_original_transaction_id: string
          billing_period: string
          billing_store: string
          business_email: string
          can_add_user: boolean
          charges_enabled: boolean
          details_submitted: boolean
          disabled_reason: string
          effective_monthly_cents: number
          entitlement_state: string
          external_payment_url: string
          grace_period_ends_at: string
          has_entitlement: boolean
          is_free_offer: boolean
          is_trial_active: boolean
          offer_identifier: string
          offer_type: number
          open_invitations: number
          payment_model: string
          payouts_enabled: boolean
          pending_user_limit: number
          period_ends_at: string
          plan_included_users: number
          plan_price_cents: number
          plan_user_limit: number
          platform_fee_bps: number
          renews_to_period: string
          renews_to_tier_id: string
          requirements_due: string[]
          seat_limits_enforced: boolean
          seats_over_limit: boolean
          stripe_account_id: string
          stripe_connected: boolean
          subscription_monthly_cents: number
          subscription_status: string
          tier_id: string
          tier_name: string
          trial_days_remaining: number
          trial_ends_at: string
          users_to_deactivate: number
          will_auto_renew: boolean
        }[]
      }
      company_currency_code: { Args: never; Returns: string }
      company_entitlement_for: {
        Args: { p_company: string }
        Returns: {
          active_users: number
          annual_cents: number
          billing_period: string
          entitlement_state: string
          has_entitlement: boolean
          included_users: number
          monthly_cents: number
          open_invitations: number
          pending_tier_id: string
          pending_user_limit: number
          seat_ceiling: number
          seats_over_limit: boolean
          tier_id: string
          tier_name: string
          user_limit: number
        }[]
      }
      company_seat_refusal: { Args: { p_company: string }; Returns: string }
      company_workspace_access: {
        Args: never
        Returns: {
          active_users: number
          has_active_subscription: boolean
          plan_name: string
          seats_over_limit: boolean
          subscription_state: string
          user_limit: number
          users_to_deactivate: number
        }[]
      }
      confirm_sms_number_release: { Args: never; Returns: boolean }
      consume_sms_credit: {
        Args: {
          p_credits?: number
          p_customer?: string
          p_job?: string
          p_notification: string
        }
        Returns: {
          balance_after: number
          credits_charged: number
          outcome: string
        }[]
      }
      convert_quote_to_job: {
        Args: {
          p_field_worker_user_id?: string
          p_kind: Database["public"]["Enums"]["job_kind"]
          p_priority: Database["public"]["Enums"]["job_priority"]
          p_quote: string
          p_scheduled_end?: string
          p_scheduled_start?: string
        }
        Returns: string
      }
      count_scheduling_conflicts: {
        Args: {
          p_end: string
          p_job: string
          p_start: string
          p_worker: string
        }
        Returns: number
      }
      create_company_and_owner: {
        Args: {
          p_country_code: string
          p_currency_code: string
          p_default_tax_rate?: number
          p_name: string
          p_owner_name?: string
          p_phone?: string
          p_time_zone_identifier: string
          p_trade: Database["public"]["Enums"]["app_trade"]
        }
        Returns: string
      }
      create_invitation: {
        Args: {
          p_email: string
          p_expires_in_days?: number
          p_role: Database["public"]["Enums"]["app_role"]
        }
        Returns: {
          invitation_id: string
          invitation_token: string
        }[]
      }
      create_invoice: {
        Args: {
          p_address_id?: string
          p_customer_id: string
          p_due_date?: string
          p_issue_date?: string
          p_payment_terms_label?: string
          p_scope_of_work?: string
          p_title?: string
        }
        Returns: string
      }
      create_invoice_from_job: {
        Args: {
          p_advance_job_status?: boolean
          p_copy_line_items?: boolean
          p_due_date?: string
          p_issue_date?: string
          p_job: string
          p_payment_terms_label?: string
        }
        Returns: string
      }
      create_invoice_from_quote: {
        Args: {
          p_advance_job_status?: boolean
          p_copy_line_items?: boolean
          p_due_date?: string
          p_issue_date?: string
          p_payment_terms_label?: string
          p_quote: string
        }
        Returns: string
      }
      create_job: {
        Args: {
          p_address_id: string
          p_customer_id: string
          p_equipment_id?: string
          p_field_worker_user_id?: string
          p_job_description: string
          p_kind: Database["public"]["Enums"]["job_kind"]
          p_priority: Database["public"]["Enums"]["job_priority"]
          p_quote_id?: string
          p_scheduled_end?: string
          p_scheduled_start?: string
          p_title: string
        }
        Returns: string
      }
      create_quote: {
        Args: {
          p_address_id: string
          p_customer_id: string
          p_scope_of_work?: string
          p_title: string
          p_valid_until?: string
        }
        Returns: string
      }
      credit_sms_purchase: {
        Args: { p_purchase: string }
        Returns: {
          balance_after: number
          credits_added: number
          outcome: string
        }[]
      }
      current_app_role: {
        Args: never
        Returns: Database["public"]["Enums"]["app_role"]
      }
      current_company_id: { Args: never; Returns: string }
      delete_invoice_line_item: {
        Args: { p_invoice: string; p_line: string }
        Returns: undefined
      }
      delete_my_account: {
        Args: { p_close_company?: boolean }
        Returns: string
      }
      delete_quote_line_item: {
        Args: { p_line: string; p_quote: string }
        Returns: undefined
      }
      dispatch_push_tick: { Args: never; Returns: number }
      engineer_create_invoice_from_job: {
        Args: { p_job: string }
        Returns: string
      }
      engineer_delete_invoice_line: {
        Args: { p_invoice: string; p_line: string }
        Returns: undefined
      }
      engineer_invoice_email_prepare: {
        Args: { p_invoice: string; p_recipient: string }
        Returns: Json
      }
      engineer_invoice_email_settle: {
        Args: {
          p_delivered: boolean
          p_failure?: string
          p_notification: string
          p_reference?: string
        }
        Returns: undefined
      }
      engineer_invoice_payment_link: {
        Args: { p_invoice: string }
        Returns: string
      }
      engineer_issue_invoice: {
        Args: { p_invoice: string }
        Returns: undefined
      }
      engineer_job_invoice: { Args: { p_job: string }; Returns: Json }
      engineer_save_invoice_line: {
        Args: {
          p_description: string
          p_invoice: string
          p_line: string
          p_quantity: number
          p_unit_price: number
        }
        Returns: undefined
      }
      engineer_scoped_invoice: {
        Args: { p_invoice: string }
        Returns: {
          address_id: string | null
          amount_paid: number
          balance: number
          billing_contact_id: string | null
          company_id: string
          created_at: string
          created_by_user_id: string | null
          currency_code: string
          customer_id: string
          due_date: string
          id: string
          issue_date: string
          job_id: string | null
          number: string
          paid_at: string | null
          payment_terms_label: string
          quote_id: string | null
          scope_of_work: string
          sent_at: string | null
          status: Database["public"]["Enums"]["invoice_status"]
          subtotal: number
          tax: number
          title: string
          total: number
          updated_at: string
          viewed_at: string | null
          voided_at: string | null
        }
        SetofOptions: {
          from: "*"
          to: "invoices"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      engineer_share_token: {
        Args: { p_company: string; p_invoice: string }
        Returns: string
      }
      enqueue_push: {
        Args: {
          p_body: string
          p_company: string
          p_customer?: string
          p_event: string
          p_job?: string
          p_title: string
          p_user: string
        }
        Returns: number
      }
      finish_scheduled_sms: {
        Args: {
          p_id: string
          p_notification: string
          p_reason: string
          p_status: string
        }
        Returns: undefined
      }
      generate_due_recurring_jobs: {
        Args: { p_company?: string; p_horizon_days?: number }
        Returns: {
          job_id: string
          outcome: string
          scheduled_for: string
          service_agreement_id: string
        }[]
      }
      has_engineer_financial_grant: {
        Args: { p_kind: string }
        Returns: boolean
      }
      has_perm: {
        Args: { p: Database["public"]["Enums"]["app_permission"] }
        Returns: boolean
      }
      is_assigned_to_job: { Args: { p_job: string }; Returns: boolean }
      is_company_field_worker: { Args: { p_user: string }; Returns: boolean }
      is_office_user: { Args: never; Returns: boolean }
      issue_invoice_share_token: {
        Args: { p_invoice: string; p_rotate?: boolean }
        Returns: string
      }
      issue_invoice_share_token_service: {
        Args: { p_company: string; p_invoice: string }
        Returns: string
      }
      issue_quote_share_token: { Args: { p_quote: string }; Returns: string }
      issue_quote_share_token_service: {
        Args: { p_company: string; p_quote: string }
        Returns: string
      }
      make_invoice: {
        Args: {
          p_address_id: string
          p_customer_id: string
          p_due_date: string
          p_issue_date: string
          p_job_id: string
          p_payment_terms_label: string
          p_quote_id: string
          p_scope_of_work: string
          p_title: string
        }
        Returns: string
      }
      mark_office_thread_read: {
        Args: { p_thread: string }
        Returns: undefined
      }
      mark_sms_conversation_read: {
        Args: { p_conversation: string }
        Returns: undefined
      }
      messaging_store_subaccount_token: {
        Args: { p_account: string; p_token: string }
        Returns: undefined
      }
      messaging_subaccount_token: {
        Args: { p_account: string }
        Returns: string
      }
      messaging_webhook_context: {
        Args: { p_callback_key: string }
        Returns: {
          auth_token: string
          company_id: string
          messaging_account_id: string
          messaging_service_sid: string
          twilio_subaccount_sid: string
        }[]
      }
      moderate_message_report: {
        Args: {
          p_action: string
          p_days?: number
          p_note?: string
          p_report: string
        }
        Returns: string
      }
      moderation_claim_alerts: {
        Args: { p_limit?: number }
        Returns: {
          alert_id: string
          attempt: number
          company_name: string
          created_at: string
          details: string
          escalated: boolean
          kind: string
          note: string
          photo_count: number
          reason: string
          report_id: string
          reported_name: string
          reported_role: string
          reporter_name: string
          reporter_role: string
          snapshot_body: string
          snapshot_meta: Json
          source: string
          status: string
        }[]
      }
      moderation_dispatch_tick: { Args: never; Returns: number }
      moderation_flag_stalled_alerts: { Args: never; Returns: number }
      moderation_mark_alert: {
        Args: { p_alert: string; p_error?: string; p_ok: boolean }
        Returns: undefined
      }
      moderation_post_dispatch: { Args: never; Returns: number }
      moderation_queue_test_alert: {
        Args: { p_note?: string }
        Returns: string
      }
      moderation_record_report: {
        Args: {
          p_body: string
          p_company: string
          p_details: string
          p_meta: Json
          p_office_message: string
          p_office_thread: string
          p_photos: string[]
          p_reason: string
          p_reported: string
          p_reporter: string
          p_sent_at: string
          p_sms_conversation: string
          p_sms_message: string
          p_source: string
        }
        Returns: string
      }
      moderation_retry_alert: { Args: { p_alert: string }; Returns: boolean }
      moderation_verify_signature: {
        Args: { p_signature: string; p_timestamp: string }
        Returns: boolean
      }
      next_document_number: {
        Args: { p_kind: Database["public"]["Enums"]["document_kind"] }
        Returns: string
      }
      next_document_number_for_company: {
        Args: {
          p_company: string
          p_kind: Database["public"]["Enums"]["document_kind"]
        }
        Returns: string
      }
      next_service_date: {
        Args: {
          p_frequency: Database["public"]["Enums"]["service_frequency"]
          p_from: string
          p_interval?: number
        }
        Returns: string
      }
      payment_terms_days: { Args: { p_label: string }; Returns: number }
      push_caller_is_service_role: { Args: never; Returns: boolean }
      push_office_recipients: {
        Args: {
          p_company: string
          p_permission: Database["public"]["Enums"]["app_permission"]
        }
        Returns: string[]
      }
      push_when_label: {
        Args: { p_company: string; p_start: string }
        Returns: string
      }
      queue_invoice_notification: {
        Args: {
          p_channel: Database["public"]["Enums"]["notification_channel"]
          p_invoice: string
          p_recipient: string
        }
        Returns: {
          balance_after: number
          credits_charged: number
          notification_id: string
          outcome: string
        }[]
      }
      quote_public_view: { Args: { p_token: string }; Returns: Json }
      quote_share_token_for: {
        Args: { p_company: string; p_quote: string; p_user: string }
        Returns: string
      }
      recalculate_invoice_totals: {
        Args: { p_invoice: string }
        Returns: undefined
      }
      recalculate_quote_totals: {
        Args: { p_quote: string }
        Returns: undefined
      }
      record_payment: {
        Args: {
          p_amount: number
          p_invoice: string
          p_method: Database["public"]["Enums"]["payment_method"]
          p_note?: string
          p_received_at?: string
          p_reference?: string
        }
        Returns: undefined
      }
      record_payment_from_stripe: {
        Args: {
          p_account?: string
          p_amount_cents: number
          p_application_fee_cents?: number
          p_charge?: string
          p_company: string
          p_currency?: string
          p_intent: string
          p_invoice: string
          p_net_cents?: number
          p_processing_fee_cents?: number
        }
        Returns: {
          amount_paid: number
          balance: number
          outcome: string
          status: string
        }[]
      }
      refund_sms_credit: {
        Args: { p_notification: string; p_reason?: string }
        Returns: {
          balance_after: number
          credits_refunded: number
          outcome: string
        }[]
      }
      register_push_device: {
        Args: {
          p_app_version?: string
          p_bundle_id?: string
          p_device_model?: string
          p_environment?: string
          p_token: string
        }
        Returns: string
      }
      reorder_quote_line_items: {
        Args: { p_ids: string[]; p_quote: string }
        Returns: undefined
      }
      report_office_message: {
        Args: { p_details?: string; p_message: string; p_reason: string }
        Returns: string
      }
      report_sms_message: {
        Args: { p_details?: string; p_message: string; p_reason: string }
        Returns: string
      }
      reschedule_job: {
        Args: {
          p_acknowledges_conflict?: boolean
          p_end?: string
          p_job: string
          p_start?: string
        }
        Returns: undefined
      }
      reserve_sms_send: {
        Args: {
          p_body: string
          p_customer: string
          p_invoice: string
          p_job: string
          p_quote: string
          p_template: string
          p_to: string
        }
        Returns: {
          balance_after: number
          conversation_id: string
          credits_charged: number
          encoding: string
          from_number: string
          messaging_account_id: string
          messaging_service_sid: string
          notification_id: string
          outcome: string
          segments: number
          to_number: string
          twilio_account_sid: string
        }[]
      }
      reserve_sms_send_service: {
        Args: {
          p_body: string
          p_company: string
          p_customer: string
          p_invoice: string
          p_job: string
          p_quote: string
          p_scheduled: string
          p_template: string
          p_to: string
        }
        Returns: {
          balance_after: number
          conversation_id: string
          credits_charged: number
          encoding: string
          from_number: string
          messaging_account_id: string
          messaging_service_sid: string
          notification_id: string
          outcome: string
          segments: number
          to_number: string
          twilio_account_sid: string
        }[]
      }
      reset_sms_template: { Args: { p_key: string }; Returns: undefined }
      resolve_due_date: {
        Args: { p_label: string; p_reference?: string }
        Returns: string
      }
      revoke_invitation: {
        Args: { p_invitation_id: string }
        Returns: undefined
      }
      revoke_invoice_share_tokens: {
        Args: { p_invoice: string }
        Returns: undefined
      }
      run_recurring_tick: { Args: { p_horizon_days?: number }; Returns: Json }
      save_invoice_line_item: {
        Args: {
          p_description: string
          p_invoice: string
          p_line: string
          p_quantity: number
          p_tax_rate: number
          p_unit_price: number
        }
        Returns: undefined
      }
      save_quote_line_item: {
        Args: {
          p_description: string
          p_line: string
          p_quantity: number
          p_quote: string
          p_tax_rate: number
          p_unit_price: number
        }
        Returns: undefined
      }
      save_sms_template: {
        Args: { p_body: string; p_key: string }
        Returns: undefined
      }
      schedule_sms: {
        Args: {
          p_body: string
          p_customer: string
          p_invoice: string
          p_job: string
          p_quote: string
          p_scheduled_for: string
          p_template: string
          p_to: string
        }
        Returns: string
      }
      seat_limits_enforced: { Args: never; Returns: boolean }
      send_office_message: {
        Args: {
          p_body?: string
          p_engineer?: string
          p_job?: string
          p_photo_ids?: string[]
          p_subject?: string
          p_thread?: string
        }
        Returns: string
      }
      set_company_payment_model: {
        Args: { p_model: Database["public"]["Enums"]["company_payment_model"] }
        Returns: undefined
      }
      set_job_vehicle: {
        Args: { p_job: string; p_vehicle: string }
        Returns: undefined
      }
      set_member_financial_permissions: {
        Args: { p_can_collect: boolean; p_can_invoice: boolean; p_user: string }
        Returns: undefined
      }
      set_my_duty_state: {
        Args: { p_state: Database["public"]["Enums"]["worker_duty_state"] }
        Returns: undefined
      }
      set_sms_automation: {
        Args: { p_enabled: boolean; p_key: string }
        Returns: undefined
      }
      settle_notification: {
        Args: {
          p_delivered: boolean
          p_failure_reason?: string
          p_notification: string
          p_provider_reference?: string
        }
        Returns: {
          balance_after: number
          credits_refunded: number
          outcome: string
        }[]
      }
      settle_push_delivery: {
        Args: {
          p_delivered: boolean
          p_failure_reason?: string
          p_invalid_token?: boolean
          p_notification: string
          p_provider_reference?: string
        }
        Returns: string
      }
      sms_apply_status: {
        Args: {
          p_account_sid: string
          p_callback_key: string
          p_error_code: string
          p_error_message: string
          p_message_sid: string
          p_price_micros?: number
          p_status: string
        }
        Returns: {
          credits_refunded: number
          outcome: string
        }[]
      }
      sms_can_administer: { Args: never; Returns: boolean }
      sms_cancel_automations: {
        Args: {
          p_invoice: string
          p_job: string
          p_keys: string[]
          p_quote: string
          p_reason: string
        }
        Returns: number
      }
      sms_charge_number_fee: { Args: { p_number: string }; Returns: string }
      sms_company_entitled: { Args: { p_company: string }; Returns: boolean }
      sms_conversation_list: {
        Args: { p_limit?: number }
        Returns: {
          conversation_id: string
          customer_id: string
          customer_name: string
          job_id: string
          job_number: string
          last_direction: string
          last_message_at: string
          last_preview: string
          opted_out: boolean
          phone_e164: string
          unread: number
        }[]
      }
      sms_credit_balance: { Args: { p_company?: string }; Returns: number }
      sms_credit_balance_for: { Args: { p_company: string }; Returns: number }
      sms_credits_per_message: { Args: never; Returns: number }
      sms_credits_per_segment: { Args: never; Returns: number }
      sms_keyword_type: {
        Args: { p_body: string; p_opt_out_type?: string }
        Returns: string
      }
      sms_maintenance_tick: { Args: never; Returns: number }
      sms_maintenance_work_waiting: { Args: never; Returns: boolean }
      sms_messaging_status: {
        Args: never
        Returns: {
          attention: string
          balance: number
          billing_state: string
          business_name: string
          can_manage: boolean
          credits_per_segment: number
          friendly_status: string
          grace_days: number
          has_subscription: boolean
          needs_number_choice: boolean
          next_fee_due_at: string
          number_fee_cents: number
          number_fee_credits: number
          number_status: string
          phone_number: string
          provisioning_step: string
          registration_route: string
          registration_status: string
          requested_number: string
          retention_days: number
          setup_fee_cents: number
          sole_prop_verification_pending: boolean
          status: string
        }[]
      }
      sms_normalise_phone: { Args: { p: string }; Returns: string }
      sms_number_monthly_fee_credits: { Args: never; Returns: number }
      sms_number_release_allowed: {
        Args: { p_number: string }
        Returns: boolean
      }
      sms_queue_automation: {
        Args: {
          p_company: string
          p_customer: string
          p_dedupe: string
          p_invoice: string
          p_job: string
          p_key: string
          p_quote: string
          p_when: string
        }
        Returns: string
      }
      sms_rate_card: {
        Args: never
        Returns: {
          cost_basis_micros_per_segment: number
          credits_per_segment: number
          grace_days: number
          margin_bps: number
          max_numbers: number
          number_monthly_fee_cents: number
          number_monthly_fee_credits: number
          retention_days: number
          setup_fee_cents: number
          target_retail_micros_per_segment: number
        }[]
      }
      sms_record_inbound: {
        Args: {
          p_account_sid: string
          p_body: string
          p_callback_key: string
          p_from: string
          p_message_sid: string
          p_messaging_service_sid: string
          p_opt_out_type?: string
          p_to: string
        }
        Returns: {
          company_id: string
          conversation_id: string
          customer_id: string
          job_id: string
          keyword: string
          notified: number
          outcome: string
        }[]
      }
      sms_record_number_purchase: {
        Args: {
          p_account: string
          p_area: string
          p_e164: string
          p_locality: string
          p_region: string
          p_sid: string
        }
        Returns: string
      }
      sms_record_provider_result: {
        Args: {
          p_accepted: boolean
          p_error: string
          p_error_code: string
          p_from: string
          p_notification: string
          p_price_micros: number
          p_segments: number
          p_sid: string
          p_status: string
        }
        Returns: {
          balance_after: number
          credits_refunded: number
          outcome: string
        }[]
      }
      sms_reserve_internal: {
        Args: {
          p_body: string
          p_company: string
          p_customer: string
          p_invoice: string
          p_job: string
          p_quote: string
          p_scheduled: string
          p_template: string
          p_to: string
          p_user: string
        }
        Returns: {
          balance_after: number
          conversation_id: string
          credits_charged: number
          encoding: string
          from_number: string
          messaging_account_id: string
          messaging_service_sid: string
          notification_id: string
          outcome: string
          segments: number
          to_number: string
          twilio_account_sid: string
        }[]
      }
      sms_segment_info: {
        Args: { p_body: string }
        Returns: {
          encoding: string
          segments: number
          units: number
        }[]
      }
      sms_send_blocker: {
        Args: { p_company: string; p_to: string }
        Returns: string
      }
      sms_send_readiness: { Args: { p_to?: string }; Returns: string }
      sms_set_opt_out: {
        Args: {
          p_account: string
          p_company: string
          p_keyword: string
          p_opted_out: boolean
          p_phone: string
          p_service: string
          p_sid: string
          p_source: string
        }
        Returns: undefined
      }
      sms_setting_int: {
        Args: { p_default: number; p_key: string }
        Returns: number
      }
      sms_template_catalog: {
        Args: never
        Returns: {
          allowed_variables: string[]
          automation_description: string
          automation_enabled: boolean
          body: string
          category: string
          context: string
          default_body: string
          is_automatable: boolean
          is_customised: boolean
          sort_order: number
          template_key: string
          title: string
        }[]
      }
      sms_template_problem: {
        Args: { p_body: string; p_key: string }
        Returns: string
      }
      sms_usage_summary: {
        Args: never
        Returns: {
          balance: number
          fees: number
          messages_failed_30d: number
          messages_received_30d: number
          messages_sent_30d: number
          purchased: number
          refunded: number
          segments_30d: number
          used: number
        }[]
      }
      sms_verify_maintenance_signature: {
        Args: { p_signature: string; p_timestamp: string }
        Returns: boolean
      }
      snapshot_quote_lines: {
        Args: { p_invoice: string; p_quote: string }
        Returns: number
      }
      subscription_entitlement_state: {
        Args: {
          p_auto_renew: boolean
          p_expires: string
          p_free_offer: boolean
          p_grace: string
          p_now?: string
          p_offer_type: number
          p_retry: boolean
          p_revoked: string
          p_store: string
        }
        Returns: string
      }
      subscription_plan_change_check: {
        Args: { p_company?: string; p_tier_id: string }
        Returns: {
          active_users: number
          allowed: boolean
          message: string
          tier_id: string
          tier_name: string
          user_limit: number
          users_to_deactivate: number
        }[]
      }
      subscription_quote: {
        Args: { p_users?: number }
        Returns: {
          active_paid_users: number
          additional_cents: number
          additional_user_cents: number
          additional_users: number
          base_cents: number
          is_over_capacity: boolean
          max_users: number
          monthly_price_cents: number
          next_user_cents: number
          tier_id: string
          tier_name: string
        }[]
      }
      subscription_state_is_entitled: {
        Args: { p_state: string }
        Returns: boolean
      }
      sync_subscription_seats: {
        Args: { p_company?: string }
        Returns: {
          active_paid_users: number
          monthly_price_cents: number
          tier_id: string
        }[]
      }
      try_advance_job: {
        Args: { p_job: string; p_to: Database["public"]["Enums"]["job_status"] }
        Returns: boolean
      }
      unblock_chat_user: { Args: { p_user: string }; Returns: undefined }
      unregister_push_device: { Args: { p_token: string }; Returns: boolean }
      update_invoice_status: {
        Args: {
          p_invoice: string
          p_to: Database["public"]["Enums"]["invoice_status"]
        }
        Returns: undefined
      }
      update_job_status: {
        Args: {
          p_job: string
          p_latitude?: number
          p_longitude?: number
          p_to: Database["public"]["Enums"]["job_status"]
        }
        Returns: undefined
      }
      update_quote_status: {
        Args: {
          p_quote: string
          p_to: Database["public"]["Enums"]["quote_status"]
        }
        Returns: undefined
      }
    }
    Enums: {
      app_permission:
        | "companyProfileRead"
        | "companyProfileManage"
        | "companyDelete"
        | "usersRead"
        | "usersManage"
        | "saasBillingRead"
        | "saasBillingManage"
        | "customersReadAll"
        | "customersReadAssignedSiteOnly"
        | "customersManage"
        | "customerBillingDetailsRead"
        | "jobsReadAll"
        | "jobsReadAssignedOnly"
        | "jobsManage"
        | "jobStatusUpdateOwn"
        | "jobStatusHistoryReadAll"
        | "calendarReadAll"
        | "calendarReadOwnOnly"
        | "assignmentsManage"
        | "jobNotesRead"
        | "jobNotesCreate"
        | "jobPhotosRead"
        | "jobPhotosCreate"
        | "equipmentRead"
        | "equipmentManage"
        | "fieldWorkerLocationReadAll"
        | "fieldWorkerLocationReadOwnOnly"
        | "quotesRead"
        | "quotesManage"
        | "quoteFinancialsRead"
        | "invoicesRead"
        | "invoicesManage"
        | "paymentsRead"
        | "paymentsManage"
        | "smsLedgerRead"
        | "smsCreditsConsume"
        | "smsCreditsPurchase"
        | "reportsOperational"
        | "reportsFinancial"
      app_role: "owner" | "admin" | "dispatcher" | "fieldWorker" | "accounts"
      app_trade:
        | "hvac"
        | "plumbing"
        | "electrical"
        | "roofing"
        | "applianceRepair"
        | "locksmith"
        | "generalMaintenance"
        | "pestControl"
        | "other"
        | "propertyServices"
        | "automotive"
      app_user_status: "active" | "invited" | "suspended"
      billing_period: "monthly" | "annual"
      billing_store: "apple" | "google" | "none"
      company_payment_model:
        | "undecided"
        | "harbourSouthPayments"
        | "externalProvider"
      customer_status: "active" | "archived"
      customer_type:
        | "residential"
        | "commercial"
        | "propertyManagement"
        | "other"
      document_kind: "quote" | "job" | "invoice"
      invoice_status:
        | "draft"
        | "sent"
        | "viewed"
        | "partPaid"
        | "paid"
        | "overdue"
        | "void"
      job_kind: "callOut" | "install" | "maintenance" | "warranty"
      job_photo_kind:
        | "before"
        | "after"
        | "part"
        | "proof"
        | "signature"
        | "during"
        | "equipment"
        | "damage"
        | "property"
        | "other"
      job_priority: "standard" | "urgent"
      job_status:
        | "scheduled"
        | "workerAssigned"
        | "travelling"
        | "arrived"
        | "inProgress"
        | "completed"
        | "invoiced"
        | "paid"
        | "cancelled"
      location_capture_event: "travelStarted" | "arrived" | "completed"
      note_visibility: "internalOnly" | "customerVisible"
      notification_channel: "sms" | "email" | "push"
      notification_status:
        | "queued"
        | "sent"
        | "delivered"
        | "failed"
        | "accepted"
        | "undelivered"
      payment_method: "card" | "ach" | "cash" | "check" | "stripe"
      payment_status:
        | "pending"
        | "succeeded"
        | "failed"
        | "refunded"
        | "processing"
        | "cancelled"
      quote_status:
        | "draft"
        | "sent"
        | "viewed"
        | "accepted"
        | "declined"
        | "expired"
      service_frequency:
        | "monthly"
        | "quarterly"
        | "semiAnnual"
        | "annual"
        | "custom"
      sms_ledger_transaction_type:
        | "purchase"
        | "consumption"
        | "refund"
        | "adjustment"
      subscription_plan:
        | "soloTrader"
        | "team"
        | "business"
        | "growingBusiness"
        | "largerBusiness"
      subscription_status:
        | "trialing"
        | "active"
        | "pastDue"
        | "cancelled"
        | "expired"
      worker_duty_state: "available" | "onBreak" | "offDuty"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_permission: [
        "companyProfileRead",
        "companyProfileManage",
        "companyDelete",
        "usersRead",
        "usersManage",
        "saasBillingRead",
        "saasBillingManage",
        "customersReadAll",
        "customersReadAssignedSiteOnly",
        "customersManage",
        "customerBillingDetailsRead",
        "jobsReadAll",
        "jobsReadAssignedOnly",
        "jobsManage",
        "jobStatusUpdateOwn",
        "jobStatusHistoryReadAll",
        "calendarReadAll",
        "calendarReadOwnOnly",
        "assignmentsManage",
        "jobNotesRead",
        "jobNotesCreate",
        "jobPhotosRead",
        "jobPhotosCreate",
        "equipmentRead",
        "equipmentManage",
        "fieldWorkerLocationReadAll",
        "fieldWorkerLocationReadOwnOnly",
        "quotesRead",
        "quotesManage",
        "quoteFinancialsRead",
        "invoicesRead",
        "invoicesManage",
        "paymentsRead",
        "paymentsManage",
        "smsLedgerRead",
        "smsCreditsConsume",
        "smsCreditsPurchase",
        "reportsOperational",
        "reportsFinancial",
      ],
      app_role: ["owner", "admin", "dispatcher", "fieldWorker", "accounts"],
      app_trade: [
        "hvac",
        "plumbing",
        "electrical",
        "roofing",
        "applianceRepair",
        "locksmith",
        "generalMaintenance",
        "pestControl",
        "other",
        "propertyServices",
        "automotive",
      ],
      app_user_status: ["active", "invited", "suspended"],
      billing_period: ["monthly", "annual"],
      billing_store: ["apple", "google", "none"],
      company_payment_model: [
        "undecided",
        "harbourSouthPayments",
        "externalProvider",
      ],
      customer_status: ["active", "archived"],
      customer_type: [
        "residential",
        "commercial",
        "propertyManagement",
        "other",
      ],
      document_kind: ["quote", "job", "invoice"],
      invoice_status: [
        "draft",
        "sent",
        "viewed",
        "partPaid",
        "paid",
        "overdue",
        "void",
      ],
      job_kind: ["callOut", "install", "maintenance", "warranty"],
      job_photo_kind: [
        "before",
        "after",
        "part",
        "proof",
        "signature",
        "during",
        "equipment",
        "damage",
        "property",
        "other",
      ],
      job_priority: ["standard", "urgent"],
      job_status: [
        "scheduled",
        "workerAssigned",
        "travelling",
        "arrived",
        "inProgress",
        "completed",
        "invoiced",
        "paid",
        "cancelled",
      ],
      location_capture_event: ["travelStarted", "arrived", "completed"],
      note_visibility: ["internalOnly", "customerVisible"],
      notification_channel: ["sms", "email", "push"],
      notification_status: [
        "queued",
        "sent",
        "delivered",
        "failed",
        "accepted",
        "undelivered",
      ],
      payment_method: ["card", "ach", "cash", "check", "stripe"],
      payment_status: [
        "pending",
        "succeeded",
        "failed",
        "refunded",
        "processing",
        "cancelled",
      ],
      quote_status: [
        "draft",
        "sent",
        "viewed",
        "accepted",
        "declined",
        "expired",
      ],
      service_frequency: [
        "monthly",
        "quarterly",
        "semiAnnual",
        "annual",
        "custom",
      ],
      sms_ledger_transaction_type: [
        "purchase",
        "consumption",
        "refund",
        "adjustment",
      ],
      subscription_plan: [
        "soloTrader",
        "team",
        "business",
        "growingBusiness",
        "largerBusiness",
      ],
      subscription_status: [
        "trialing",
        "active",
        "pastDue",
        "cancelled",
        "expired",
      ],
      worker_duty_state: ["available", "onBreak", "offDuty"],
    },
  },
} as const
