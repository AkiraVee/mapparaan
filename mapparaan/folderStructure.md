mapparaan/
├── android/
│   ├── app/
│   │   └── src/
│   │       ├── debug/AndroidManifest.xml
│   │       ├── main/
│   │       │   ├── java/io/flutter/plugins/GeneratedPluginRegistrant.java
│   │       │   ├── kotlin/com/example/mapparaan/MainActivity.kt
│   │       │   └── res/
│   │       │       ├── drawable/launch_background.xml
│   │       │       ├── drawable-v21/launch_background.xml
│   │       │       ├── mipmap-hdpi/ic_launcher.png
│   │       │       ├── mipmap-mdpi/ic_launcher.png
│   │       │       ├── mipmap-xhdpi/ic_launcher.png
│   │       │       ├── mipmap-xxhdpi/ic_launcher.png
│   │       │       ├── mipmap-xxxhdpi/ic_launcher.png
│   │       │       ├── values/styles.xml
│   │       │       └── values-night/styles.xml
│   │       └── profile/AndroidManifest.xml
│   ├── gradle/wrapper/gradle-wrapper.properties
│   ├── .gitignore
│   ├── app/build.gradle.kts
│   ├── build.gradle.kts
│   ├── gradle.properties
│   ├── local.properties
│   └── settings.gradle.kts
├── backend/
│   ├── planner/
│   │   ├── __init__.py
│   │   ├── api.py
│   │   ├── check_all.py
│   │   ├── gtfs_planner.py
│   │   ├── test_api_security.py
│   │   ├── test_fares.py
│   │   ├── test_service_days.py
│   │   └── test_trips.py
│   └── __init__.py
├── data/
│   ├── gtfs/
│   │   ├── agency.txt
│   │   ├── calendar.txt
│   │   ├── feed_info.txt
│   │   ├── frequencies.txt
│   │   ├── routes.txt
│   │   ├── shapes.txt
│   │   ├── stop_times.txt
│   │   ├── stops.txt
│   │   ├── trips.txt
│   │   ├── LICENSE.md
│   │   └── README.md
│   ├── gtfs_backup_before_drop_pnr/
│   │   ├── agency.txt
│   │   ├── calendar.txt
│   │   ├── frequencies.txt
│   │   ├── routes.txt
│   │   ├── shapes.txt
│   │   ├── stop_times.txt
│   │   ├── stops.txt
│   │   └── trips.txt
│   ├── reference/
│   │   ├── fare_config.json
│   │   ├── manifest.json
│   │   ├── manila_boundary.geojson
│   │   └── route_modes.csv
│   ├── tools/
│   │   ├── clip_gtfs.py
│   │   ├── drop_pnr.py
│   │   └── patch_gtfs.py
│   └── README.md
├── docs/
│   ├── dfd_level_0.drawio
│   ├── dfd_level_1.drawio
│   ├── dfd_level_2.drawio
│   ├── final_dfd_level_0.drawio
│   ├── final_dfd_level_0.jpg
│   ├── final_dfd_level_0.png
│   ├── final_dfd_level_1.drawio
│   ├── supabase_erd.drawio
│   ├── supabase_erd.md
│   └── system_dfd_report.md
├── ios/
│   ├── Flutter/
│   │   ├── AppFrameworkInfo.plist
│   │   ├── Debug.xcconfig
│   │   ├── Release.xcconfig
│   │   ├── Generated.xcconfig
│   │   └── flutter_export_environment.sh
│   ├── Runner/
│   │   ├── Assets.xcassets/
│   │   │   ├── AppIcon.appiconset/
│   │   │   │   ├── Contents.json
│   │   │   │   └── app icon PNGs
│   │   │   └── LaunchImage.imageset/
│   │   │       ├── Contents.json
│   │   │       ├── LaunchImage.png
│   │   │       ├── LaunchImage@2x.png
│   │   │       ├── LaunchImage@3x.png
│   │   │       └── README.md
│   │   ├── Base.lproj/
│   │   │   ├── LaunchScreen.storyboard
│   │   │   └── Main.storyboard
│   │   ├── AppDelegate.swift
│   │   ├── GeneratedPluginRegistrant.h
│   │   ├── GeneratedPluginRegistrant.m
│   │   ├── Info.plist
│   │   ├── Runner-Bridging-Header.h
│   │   └── SceneDelegate.swift
│   ├── Runner.xcodeproj/
│   │   ├── project.xcworkspace/
│   │   │   └── contents.xcworkspacedata
│   │   ├── xcshareddata/xcschemes/Runner.xcscheme
│   │   └── project.pbxproj
│   ├── Runner.xcworkspace/
│   │   ├── xcshareddata/IDEWorkspaceChecks.plist
│   │   └── contents.xcworkspacedata
│   ├── RunnerTests/RunnerTests.swift
│   └── .gitignore
├── lib/
│   ├── screens/
│   │   ├── auth_screen.dart
│   │   ├── drawer_destination_screen.dart
│   │   ├── friends_screen.dart
│   │   ├── home_screen.dart
│   │   ├── location_details_screen.dart
│   │   ├── location_disabled_screen.dart
│   │   └── search_location_screen.dart
│   ├── services/
│   │   ├── ai_assistant_service.dart
│   │   ├── auth_service.dart
│   │   ├── commuter_preference_service.dart
│   │   ├── friend_sharing_service.dart
│   │   ├── last_route_service.dart
│   │   ├── local_ui_preferences_service.dart
│   │   ├── memory_photo_compression_service.dart
│   │   ├── memory_pin_service.dart
│   │   ├── place_search_service.dart
│   │   ├── route_planner_service.dart
│   │   ├── saved_commute_service.dart
│   │   ├── saved_places_service.dart
│   │   ├── transit_planner_service.dart
│   │   ├── trip_history_service.dart
│   │   └── walk_route_service.dart
│   ├── utils/geo_point_parser.dart
│   ├── widgets/
│   │   ├── circle_icon_button.dart
│   │   ├── mapparaan_drawer.dart
│   │   ├── mapparaan_tile_layer.dart
│   │   └── photo_sharing_dialog.dart
│   ├── constants.dart
│   └── main.dart
├── supabase/
│   └── migrations/
│       ├── 20261022_private_memory_photos_and_saved_place_ids.sql
│       ├── 20261023_normalize_and_harden_access.sql
│       ├── 20261027_friend_shared_photo_locations.sql
│       ├── 20261028_normalize_memory_pin_shares.sql
│       ├── 20261028_optimize_rls_initialization.sql
│       ├── Actibe photo uploading.sql
│       └── Fix storage listing.sql
├── test/
│   ├── color_vision_filter_test.dart
│   ├── location_details_screen_test.dart
│   ├── memory_photo_compression_test.dart
│   ├── memory_pin_service_test.dart
│   ├── photo_sharing_dialog_test.dart
│   └── transit_planner_test.dart
├── web/
│   ├── icons/
│   │   ├── Icon-192.png
│   │   ├── Icon-512.png
│   │   ├── Icon-maskable-192.png
│   │   └── Icon-maskable-512.png
│   ├── favicon.png
│   ├── index.html
│   └── manifest.json
├── .dockerignore
├── .env
├── .env.example
├── .flutter-plugins-dependencies
├── .gitignore
├── .metadata
├── analysis_options.yaml
├── Dockerfile
├── GEMINI.md
├── pubspec.lock
├── pubspec.yaml
└── README.md