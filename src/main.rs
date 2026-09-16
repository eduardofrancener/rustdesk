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
