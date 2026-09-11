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
    PostgrestVersion: "14.5"
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
      companies: {
        Row: {
          address_line: string
          business_email: string | null
          city: string
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
      company_subscriptions: {
        Row: {
          active_paid_users: number
          additional_user_cents: number
          additional_users: number
          apple_original_transaction_id: string | null
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
          apple_original_transaction_id?: string | null
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
          apple_original_transaction_id?: string | null
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
          job_id: string
          kind: Database["public"]["Enums"]["job_photo_kind"]
          storage_reference: string
          user_id: string
        }
        Insert: {
          caption?: string | null
          captured_at?: string
          company_id: string
          id?: string
          job_id: string
          kind?: Database["public"]["Enums"]["job_photo_kind"]
          storage_reference: string
          user_id: string
        }
        Update: {
          caption?: string | null
          captured_at?: string
          company_id?: string
          id?: string
          job_id?: string
          kind?: Database["public"]["Enums"]["job_photo_kind"]
          storage_reference?: string
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
        ]
      }
      notifications: {
        Row: {
          body: string | null
          channel: Database["public"]["Enums"]["notification_channel"]
          claimed_at: string | null
          company_id: string
          created_at: string
          credits_charged: number
          credits_refunded: number
          customer_id: string | null
          deep_link: string | null
          delivered_at: string | null
          failure_reason: string | null
          from_number: string | null
          id: string
          invoice_id: string | null
          job_id: string | null
          provider_error: string | null
          provider_reference: string | null
          provider_status: string | null
          push_device_id: string | null
          recipient: string
          segments: number | null
          sent_at: string | null
          status: Database["public"]["Enums"]["notification_status"]
          target_user_id: string | null
          template: string
          title: string | null
          to_number: string | null
          updated_at: string
        }
        Insert: {
          body?: string | null
          channel: Database["public"]["Enums"]["notification_channel"]
          claimed_at?: string | null
          company_id: string
          created_at?: string
          credits_charged?: number
          credits_refunded?: number
          customer_id?: string | null
          deep_link?: string | null
          delivered_at?: string | null
          failure_reason?: string | null
          from_number?: string | null
          id?: string
          invoice_id?: string | null
          job_id?: string | null
          provider_error?: string | null
          provider_reference?: string | null
          provider_status?: string | null
          push_device_id?: string | null
          recipient?: string
          segments?: number | null
          sent_at?: string | null
          status?: Database["public"]["Enums"]["notification_status"]
          target_user_id?: string | null
          template?: string
          title?: string | null
          to_number?: string | null
          updated_at?: string
        }
        Update: {
          body?: string | null
          channel?: Database["public"]["Enums"]["notification_channel"]
          claimed_at?: string | null
          company_id?: string
          created_at?: string
          credits_charged?: number
          credits_refunded?: number
          customer_id?: string | null
          deep_link?: string | null
          delivered_at?: string | null
          failure_reason?: string | null
          from_number?: string | null
          id?: string
          invoice_id?: string | null
          job_id?: string | null
          provider_error?: string | null
          provider_reference?: string | null
          provider_status?: string | null
          push_device_id?: string | null
          recipient?: string
          segments?: number | null
          sent_at?: string | null
          status?: Database["public"]["Enums"]["notification_status"]
          target_user_id?: string | null
          template?: string
          title?: string | null
          to_number?: string | null
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
            foreignKeyName: "notifications_push_device_id_fkey"
            columns: ["push_device_id"]
            isOneToOne: false
            referencedRelation: "push_devices"
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
          base_cents: number
          display_name: string
          id: string
          is_active: boolean
          max_users: number
          min_users: number
          sort_order: number
          updated_at: string
        }
        Insert: {
          additional_user_cents: number
          base_cents: number
          display_name: string
          id: string
          is_active?: boolean
          max_users: number
          min_users: number
          sort_order?: number
          updated_at?: string
        }
        Update: {
          additional_user_cents?: number
          base_cents?: number
          display_name?: string
          id?: string
          is_active?: boolean
          max_users?: number
          min_users?: number
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
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
    }
    Functions: {
      accept_invitation: { Args: { p_token: string }; Returns: string }
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
      claim_founding_member_slot: {
        Args: { p_company?: string }
        Returns: number
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
          activity_month_start: string
          business_email: string
          charges_enabled: boolean
          details_submitted: boolean
          disabled_reason: string
          effective_monthly_cents: number
          external_payment_url: string
          founding_benefit_active: boolean
          founding_claimed_at: string
          founding_member_number: number
          founding_offer_open: boolean
          founding_places_claimed: number
          founding_places_remaining: number
          is_trial_active: boolean
          last_qualifying_payment_at: string
          payment_model: string
          payouts_enabled: boolean
          platform_fee_bps: number
          qualifying_payments_this_month: number
          requirements_due: string[]
          stripe_account_id: string
          stripe_connected: boolean
          subscription_monthly_cents: number
          subscription_status: string
          tier_id: string
          tier_name: string
          trial_days_remaining: number
          trial_ends_at: string
        }[]
      }
      company_currency_code: { Args: never; Returns: string }
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
      delete_quote_line_item: {
        Args: { p_line: string; p_quote: string }
        Returns: undefined
      }
      dispatch_push_tick: { Args: never; Returns: number }
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
      founding_activity: {
        Args: { p_company?: string }
        Returns: {
          last_qualifying_payment_at: string
          month_start: string
          qualifying_payments: number
        }[]
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
      reschedule_job: {
        Args: {
          p_acknowledges_conflict?: boolean
          p_end?: string
          p_job: string
          p_start?: string
        }
        Returns: undefined
      }
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
      set_my_duty_state: {
        Args: { p_state: Database["public"]["Enums"]["worker_duty_state"] }
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
      sms_credit_balance: { Args: { p_company?: string }; Returns: number }
      sms_credit_balance_for: { Args: { p_company: string }; Returns: number }
      sms_credits_per_message: { Args: never; Returns: number }
      snapshot_quote_lines: {
        Args: { p_invoice: string; p_quote: string }
        Returns: number
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
      job_photo_kind: "before" | "after" | "part" | "proof" | "signature"
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
      job_photo_kind: ["before", "after", "part", "proof", "signature"],
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
