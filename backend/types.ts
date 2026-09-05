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
          city: string
          country_code: string
          created_at: string
          currency_code: string
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
          city?: string
          country_code: string
          created_at?: string
          currency_code: string
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
          city?: string
          country_code?: string
          created_at?: string
          currency_code?: string
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
          additional_users: number
          apple_original_transaction_id: string | null
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
          plan: Database["public"]["Enums"]["subscription_plan"]
          renewal_date: string
          seat_count: number
          status: Database["public"]["Enums"]["subscription_status"]
          store: Database["public"]["Enums"]["billing_store"]
          trial_ends_at: string | null
          updated_at: string
        }
        Insert: {
          additional_users?: number
          apple_original_transaction_id?: string | null
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
          plan?: Database["public"]["Enums"]["subscription_plan"]
          renewal_date?: string
          seat_count?: number
          status?: Database["public"]["Enums"]["subscription_status"]
          store?: Database["public"]["Enums"]["billing_store"]
          trial_ends_at?: string | null
          updated_at?: string
        }
        Update: {
          additional_users?: number
          apple_original_transaction_id?: string | null
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
          plan?: Database["public"]["Enums"]["subscription_plan"]
          renewal_date?: string
          seat_count?: number
          status?: Database["public"]["Enums"]["subscription_status"]
          store?: Database["public"]["Enums"]["billing_store"]
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
          id: string
          installed_on: string
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
          id?: string
          installed_on: string
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
          id?: string
          installed_on?: string
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
          customer_id: string | null
          deep_link: string | null
          delivered_at: string | null
          failure_reason: string | null
          id: string
          invoice_id: string | null
          job_id: string | null
          provider_reference: string | null
          push_device_id: string | null
          recipient: string
          sent_at: string | null
          status: Database["public"]["Enums"]["notification_status"]
          target_user_id: string | null
          template: string
          title: string | null
        }
        Insert: {
          body?: string | null
          channel: Database["public"]["Enums"]["notification_channel"]
          claimed_at?: string | null
          company_id: string
          created_at?: string
          customer_id?: string | null
          deep_link?: string | null
          delivered_at?: string | null
          failure_reason?: string | null
          id?: string
          invoice_id?: string | null
          job_id?: string | null
          provider_reference?: string | null
          push_device_id?: string | null
          recipient?: string
          sent_at?: string | null
          status?: Database["public"]["Enums"]["notification_status"]
          target_user_id?: string | null
          template?: string
          title?: string | null
        }
        Update: {
          body?: string | null
          channel?: Database["public"]["Enums"]["notification_channel"]
          claimed_at?: string | null
          company_id?: string
          created_at?: string
          customer_id?: string | null
          deep_link?: string | null
          delivered_at?: string | null
          failure_reason?: string | null
          id?: string
          invoice_id?: string | null
          job_id?: string | null
          provider_reference?: string | null
          push_device_id?: string | null
          recipient?: string
          sent_at?: string | null
          status?: Database["public"]["Enums"]["notification_status"]
          target_user_id?: string | null
          template?: string
          title?: string | null
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
      payments: {
        Row: {
          amount: number
          company_id: string
          created_at: string
          id: string
          invoice_id: string
          is_simulated: boolean
          method: Database["public"]["Enums"]["payment_method"]
          note: string | null
          received_at: string
          recorded_by_user_id: string
          reference: string | null
          status: Database["public"]["Enums"]["payment_status"]
        }
        Insert: {
          amount: number
          company_id: string
          created_at?: string
          id?: string
          invoice_id: string
          is_simulated?: boolean
          method: Database["public"]["Enums"]["payment_method"]
          note?: string | null
          received_at?: string
          recorded_by_user_id: string
          reference?: string | null
          status?: Database["public"]["Enums"]["payment_status"]
        }
        Update: {
          amount?: number
          company_id?: string
          created_at?: string
          id?: string
          invoice_id?: string
          is_simulated?: boolean
          method?: Database["public"]["Enums"]["payment_method"]
          note?: string | null
          received_at?: string
          recorded_by_user_id?: string
          reference?: string | null
          status?: Database["public"]["Enums"]["payment_status"]
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
          is_active: boolean
          next_due_date: string
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
          is_active?: boolean
          next_due_date: string
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
          is_active?: boolean
          next_due_date?: string
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
      company_currency_code: { Args: never; Returns: string }
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
      has_perm: {
        Args: { p: Database["public"]["Enums"]["app_permission"] }
        Returns: boolean
      }
      is_assigned_to_job: { Args: { p_job: string }; Returns: boolean }
      is_company_field_worker: { Args: { p_user: string }; Returns: boolean }
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
      next_document_number: {
        Args: { p_kind: Database["public"]["Enums"]["document_kind"] }
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
      revoke_invitation: {
        Args: { p_invitation_id: string }
        Returns: undefined
      }
      revoke_invoice_share_tokens: {
        Args: { p_invoice: string }
        Returns: undefined
      }
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
      sms_credits_per_message: { Args: never; Returns: number }
      snapshot_quote_lines: {
        Args: { p_invoice: string; p_quote: string }
        Returns: number
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
      job_photo_kind: "before" | "after" | "part" | "proof"
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
      notification_status: "queued" | "sent" | "delivered" | "failed"
      payment_method: "card" | "ach" | "cash" | "check"
      payment_status: "pending" | "succeeded" | "failed" | "refunded"
      quote_status:
        | "draft"
        | "sent"
        | "viewed"
        | "accepted"
        | "declined"
        | "expired"
      service_frequency: "monthly" | "quarterly" | "semiAnnual" | "annual"
      sms_ledger_transaction_type:
        | "purchase"
        | "consumption"
        | "refund"
        | "adjustment"
      subscription_plan: "soloTrader" | "team" | "business"
      subscription_status:
        | "trialing"
        | "active"
        | "pastDue"
        | "cancelled"
        | "expired"
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
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
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
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
      job_photo_kind: ["before", "after", "part", "proof"],
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
      notification_status: ["queued", "sent", "delivered", "failed"],
      payment_method: ["card", "ach", "cash", "check"],
      payment_status: ["pending", "succeeded", "failed", "refunded"],
      quote_status: [
        "draft",
        "sent",
        "viewed",
        "accepted",
        "declined",
        "expired",
      ],
      service_frequency: ["monthly", "quarterly", "semiAnnual", "annual"],
      sms_ledger_transaction_type: [
        "purchase",
        "consumption",
        "refund",
        "adjustment",
      ],
      subscription_plan: ["soloTrader", "team", "business"],
      subscription_status: [
        "trialing",
        "active",
        "pastDue",
        "cancelled",
        "expired",
      ],
    },
  },
} as const
