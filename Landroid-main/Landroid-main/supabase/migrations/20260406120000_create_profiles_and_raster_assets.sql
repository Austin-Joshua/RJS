-- Apply in Supabase SQL editor or via CLI if the MCP migration tool is unavailable.
-- Profiles: synced from the Flutter app after Google + Supabase sign-in.

CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  email text,
  full_name text,
  avatar_url text,
  locale text DEFAULT 'en',
  app_role text DEFAULT 'consultant',
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS profiles_email_idx ON public.profiles (email);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
CREATE POLICY "profiles_select_own" ON public.profiles
  FOR SELECT USING (auth.uid() = id);

DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
CREATE POLICY "profiles_insert_own" ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE USING (auth.uid() = id);

-- Raster metadata (filled by scripts/backend; optional reads for signed-in users)
CREATE TABLE IF NOT EXISTS public.raster_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  file_name text NOT NULL,
  kind text,
  crs text,
  width int,
  height int,
  bounds jsonb,
  stats jsonb,
  source_pdf_path text,
  created_at timestamptz DEFAULT now() NOT NULL
);

ALTER TABLE public.raster_assets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "raster_assets_authenticated_read" ON public.raster_assets;
CREATE POLICY "raster_assets_authenticated_read" ON public.raster_assets
  FOR SELECT TO authenticated USING (true);
