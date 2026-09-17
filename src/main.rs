#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use librustdesk::*;

fn configure_araquaridesk() {
    let is_admin = std::env::args().any(|arg| arg == "--araquari-admin");
    let display_name = std::env::args()
        .find_map(|arg| arg.strip_prefix("--araquari-display-name=").map(str::to_owned))
        .unwrap_or_default();

    fn apply_profile(is_admin: bool, display_name: &str) {
        *hbb_common::config::APP_NAME.write().unwrap() = "AraquariDesk".to_owned();

        hbb_common::config::Config::set_option(
            "custom-rendezvous-server".to_owned(),
            "jiraiya.araquari.sc.gov.br".to_owned(),
        );
        hbb_common::config::Config::set_option(
            "relay-server".to_owned(),
            "jiraiya.araquari.sc.gov.br".to_owned(),
        );
        hbb_common::config::Config::set_option("api-server".to_owned(), "".to_owned());
        hbb_common::config::Config::set_option(
            "key".to_owned(),
            "11CvwLZ0myJrVOg2amrOhqcKC0gZD1XIiFyL6QBnt+0=".to_owned(),
        );

        {
            let mut hard_settings = hbb_common::config::HARD_SETTINGS.write().unwrap();
            hard_settings.insert(
                "conn-type".to_owned(),
                if is_admin {
                    "bidirectional".to_owned()
                } else {
                    "incoming".to_owned()
                },
            );
        }

        // The existing connection handshake uses user_info.display_name as
        // LoginRequest.my_name. Keep it synchronized with the authenticated TI.
        let mut user_info: serde_json::Value =
            serde_json::from_str(&hbb_common::config::LocalConfig::get_option("user_info"))
                .unwrap_or_else(|_| serde_json::json!({}));
        if let Some(obj) = user_info.as_object_mut() {
            if is_admin && !display_name.is_empty() {
                obj.insert(
                    "display_name".to_owned(),
                    serde_json::Value::String(display_name.to_owned()),
                );
            } else {
                obj.remove("display_name");
            }
        }
        if let Ok(serialized) = serde_json::to_string(&user_info) {
            hbb_common::config::LocalConfig::set_option("user_info".to_owned(), serialized);
        }
        hbb_common::config::LocalConfig::set_option(
            "display-name".to_owned(),
            if is_admin {
                display_name.to_owned()
            } else {
                String::new()
            },
        );
    }

    apply_profile(is_admin, &display_name);

    // Flutter loads custom.txt after main(). Re-apply the fixed profile during
    // startup so a common-user build cannot regain outgoing access because of
    // values loaded from the custom-client configuration.
    std::thread::spawn(move || {
        for delay_ms in [400_u64, 1200, 2500] {
            std::thread::sleep(std::time::Duration::from_millis(delay_ms));
            apply_profile(is_admin, &display_name);
        }
    });
}

#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
fn main() {
    configure_araquaridesk();
    if !common::global_init() {
        eprintln!("Global initialization failed.");
        return;
    }
    common::test_rendezvous_server();
    common::test_nat_type();
    common::global_clean();
}

#[cfg(not(any(
    target_os = "android",
    target_os = "ios",
    feature = "flutter"
)))]
fn main() {
    #[cfg(all(windows, not(feature = "inline")))]
    unsafe {
        winapi::um::shellscalingapi::SetProcessDpiAwareness(2);
    }
    configure_araquaridesk();
    if let Some(args) = crate::core_main::core_main().as_mut() {
        ui::start(args);
    }
    common::global_clean();
}
