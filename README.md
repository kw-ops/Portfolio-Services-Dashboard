# Portfolio Services Dashboard (PSD)

Creates a public portfolio page for each service provider (Plug Doctor, barbers, drivers…) and gives each provider a dashboard to receive and manage service requests from Campus Stay Ghana students.

Providers are **not** typed in here. They're imported from Campus Stay's Firebase (`campus-stay-gh`, collection `service_providers`), automatically every 30 minutes or on demand with **Sync from Campus Stay**. Campus Stay owns the business details. PSD adds the public link, provider logins, the request inbox and optional extras (logo, tagline, hours, prices, extra photos).

```
Campus Stay app → Services → Plug Doctor → opens the PSD link
   └─► #/p/plug-doctor?source=campus_stay   (public portfolio)
         └─► Request a service              (student fills the form)
               └─► Plug Doctor's dashboard  (#/dashboard — live inbox)
```

| Part | Where |
|---|---|
| Web app (Flutter) | GitHub Pages |
| Data, logins, images, backend | Firebase project `portfolio-services-dashboard` (Blaze) |

## Pages

| URL (after `#`) | Who | What |
|---|---|---|
| `/p/<slug>` | Students | Public portfolio. **This is the link you paste into Campus Stay** (with `?source=campus_stay`) |
| `/p/<slug>/request` | Students | Service request form (no account needed) |
| `/login` | Admin + providers | Sign in |
| `/dashboard` | Provider | Request inbox, status updates, edit own portfolio |
| `/admin` | You | Sync providers from Campus Stay, copy links, create provider logins, see all requests |

## Project layout

```
lib/
  public/      portfolio page, request form, landing page
  provider/    provider dashboard, request detail, portfolio editor
  admin/       admin dashboard (Campus Stay sync), provider detail, all requests
  auth/        login
  data/api.dart        all Firebase calls
  config.dart          categories, statuses, link builder
  firebase_options.dart
functions/index.js     Cloud Functions (syncCampusStay, claimAdmin, createProviderAccount,
                       submitRequest, updateRequestStatus)
firestore.rules        who can read/write which data
storage.rules          public portfolio images vs private request photos
.github/workflows/     auto-deploy to GitHub Pages on push to main
```

## One-time setup

### 1. Firebase console (project `portfolio-services-dashboard`)
1. **Upgrade to Blaze**: Project settings → Usage and billing → Modify plan. Pick the same billing account as Campus Stay, then set a budget alert in Google Cloud Billing.
2. **Authentication** → Sign-in method → enable **Google** (your admin login), **Email/Password** (provider logins) and **Anonymous** (students submit requests with an anonymous session).
3. **Firestore Database** → Create database → production mode → location `europe-west1` (or the closest one offered).
4. **Storage** → Get started → production mode.

### 2. Deploy the backend (rules, indexes, functions)
```bash
firebase login
firebase deploy --only firestore,storage,functions
```
The first deploy asks for **`ADMIN_EMAIL`**. Enter the Google email you will sign in with as admin. It's saved in `functions/.env.portfolio-services-dashboard`, which is git-ignored, so your email doesn't appear in the public repo.

Optional, for faster image loading on web:
```bash
gcloud storage buckets update gs://portfolio-services-dashboard.firebasestorage.app --cors-file=cors.json
```

### 3. Let PSD read Campus Stay (one time)
PSD's functions read Campus Stay's `service_providers` with read-only access. Grant it once (you need Owner on `campus-stay-gh`):
```bash
gcloud projects add-iam-policy-binding campus-stay-gh   --member="serviceAccount:145815525368-compute@developer.gserviceaccount.com"   --role="roles/datastore.viewer"
```
To remove it later, run the same command with `remove-iam-policy-binding`.

### 4. Become the admin (one time)
Open `#/login` and tap **Admin: continue with Google**, then choose the account that matches `ADMIN_EMAIL`.

The first successful sign-in claims the admin role, and `config/admin` then locks it to that Google account permanently. Any other Google account that tries is signed straight back out. To move admin to a different account later, delete `config/admin` and that user's `users/{uid}` document in the Firestore console, change `ADMIN_EMAIL`, and redeploy the functions.

### 5. Run locally
```bash
flutter run -d chrome
```
Open `http://localhost:<port>/#/login` and sign in.

### 6. Publish on GitHub Pages
1. Create a GitHub repo and push this folder to the `main` branch. The repo name becomes part of every link, so choose it before sharing any links.
2. Repo → Settings → Pages → Source: **GitHub Actions**. Every push to `main` then builds and deploys automatically.
3. Firebase → Authentication → Settings → **Authorized domains** → add `<your-username>.github.io`.

The site is then at `https://<your-username>.github.io/<repo-name>/`.

## Adding a provider (e.g. Plug Doctor)
1. Add or edit the service in **Campus Stay admin → Services**, as you do today.
2. Within 30 minutes it appears in PSD `/admin`. To see it immediately, tap **Sync from Campus Stay**.
3. Open it in PSD → **Create login** for the provider → **Copy link**.
4. Paste the link into that service's **Visit URL** in Campus Stay admin.

Hiding a service in Campus Stay hides its portfolio in PSD. Deleting it there marks it "Deleted in Campus Stay"; its past requests and link are kept. The link is fixed on first import and never changes, even if the business is renamed.

## Request lifecycle
`pending (New) → accepted → scheduled → in_progress → completed`. A pending request can be `rejected`, and an active one can be `cancelled`. The `updateRequestStatus` function enforces these transitions, and every change is recorded in the request's history.

## Not built yet
- Push/email notifications to providers (the dashboard updates live while it's open)
- App Check (reCAPTCHA) on the request form
- Students tracking their request status
- Quotes, payments, reviews
