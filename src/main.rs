#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use librustdesk::*;

fn configure_araquaridesk() {
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

    // AraquariDesk starts in the safe, incoming-only profile. The authenticated
    // TI launcher restarts the executable with --araquari-admin after a successful
    // local login, which switches the Rust connection policy to bidirectional.
    let is_admin = std::env::args().any(|arg| arg == "--araquari-admin");
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

    // The existing RustDesk connection handshake already sends the local
    // `display-name` as LoginRequest.my_name. Keep the authenticated TI name in
    // the local config for the lifetime of the admin process and clear it for the
    // common-user process.
    let display_name = std::env::args()
        .find_map(|arg| arg.strip_prefix("--araquari-display-name=").map(str::to_owned))
        .unwrap_or_default();
    hbb_common::config::LocalConfig::set_option(
        "display-name".to_owned(),
        if is_admin { display_name } else { String::new() },
    );
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
