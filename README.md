# Just Task It ✅

A personal task tracking app built with Flutter and Supabase. You can sign up, log in, and manage your daily tasks — add them, check them off, edit them, swipe to delete, and watch your progress bar fill up as you get things done.

---

## What's Inside

- Email/password authentication via Supabase
- Add, edit, delete, and toggle tasks
- Progress tracker showing how many tasks you've completed
- Tasks split into Pending and Completed sections
- Dark mode with preference saved across sessions
- Optimistic UI updates — changes feel instant
- Responsive layout that works across phone sizes

---

## Tech Stack

| Tool | Purpose |
|---|---|
| Flutter | UI framework |
| Supabase | Auth + database |
| GetX | State management, routing, DI |
| GetStorage | Persisting dark mode preference |
| Google Fonts | Typography (Poppins, Cedarville Cursive) |

---

## Folder Structure

lib/
├── app/
│ ├── data/
│ │ ├── models/
│ │ │ └── task_model.dart
│ │ └── services/
│ │ ├── auth_service.dart
│ │ └── task_service.dart
│ ├── modules/
│ │ ├── splash/
│ │ ├── get_started/
│ │ ├── signup/
│ │ ├── login/
│ │ ├── dashboard/
│ │ │ ├── bindings/
│ │ │ ├── controllers/
│ │ │ └── views/
│ │ │ └── widgets/
│ │ └── theme/
│ ├── routes/
│ │ ├── app_pages.dart
│ │ └── app_routes.dart
│ └── theme/
│ └── app_theme.dart
└── main.dart


### App Flow

Launch
  ↓
Splash Screen (2s)
  ↓
Already logged in? → Dashboard
Not logged in?     → Get Started
                        ↓
                   Sign Up / Sign In
                        ↓
                     Dashboard
                        ↓
              Add / Edit / Delete / Toggle tasks


---

## Getting Started

### 1. Clone the repo

``bash
git clone https://github.com/yourusername/just_task_it.git
cd just_task_it
### 2. Install dependencies
flutter pub get

### 3. Set up Supabase (see section below)

### 4. Run the app
 flutter run



Hot Reload vs Hot Restart
These are two different ways to refresh your app while developing and knowing which to use saves a lot of confusion.

Hot Reload (r in terminal / ⚡ in VS Code)
Injects your code changes into the running app without restarting it. The app state is preserved — so if you're on the dashboard with tasks loaded, they stay loaded. Use this for UI tweaks, style changes, or anything visual.

The limitation is that it won't re-run initState, onInit, or main(). So if you change something in those places, hot reload won't pick it up.

Hot Restart (R in terminal / Ctrl+Shift+F5 in VS Code)
Fully restarts the app from scratch including main(), but doesn't reinstall it on the device. It's slower than hot reload but faster than a full rebuild. Use this when you:

Change something in main() like Supabase keys

Add a new package and want it to initialize

Change a controller's onInit logic

Something feels stale and hot reload isn't reflecting changes

Full Rebuild (flutter run)
Recompiles the entire app. You need this when you add new native dependencies or change anything in AndroidManifest.xml or Info.plist.



