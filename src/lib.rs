#[macro_use]
extern crate rocket;

// Re-export the rocket builder function for integration tests
mod error;
mod handlers;
mod guards;
mod subscribers;
mod ops;

// Re-export these modules for use in main.rs
pub mod store;
pub mod config;

use rocket_okapi::settings::UrlObject;
use rocket_okapi::swagger_ui::make_swagger_ui;
use rocket_okapi::{openapi_get_routes, rapidoc::*, swagger_ui::*};
use tokio::sync::Mutex;

use crate::store::Store;

/// Generate and print the OpenAPI specification
pub fn print_openapi_spec() {
    let settings = rocket_okapi::settings::OpenApiSettings::new();
    let spec = rocket_okapi::openapi_spec![
        handlers::ip::borrow,
        handlers::ip::return_item,
        handlers::ip::submit_item,
        handlers::ip::get_operation_status,
    ](&settings);
    println!("{}", serde_json::to_string_pretty(&spec).unwrap());
}

pub struct AppState {
    redis_url: String,
    config: config::AppConfig,
    subs: subscribers::Subscribers,
    ops: ops::OperationStore,
    sse: ops::Broadcasters,
}

/// Build and configure the Rocket instance
/// This function is public to allow integration tests to use it
pub fn rocket(redis_url: String) -> rocket::Rocket<rocket::Build> {
    rocket_with_config(redis_url, config::AppConfig::default())
}

/// Build and configure the Rocket instance with custom config
pub fn rocket_with_config(redis_url: String, app_config: config::AppConfig) -> rocket::Rocket<rocket::Build> {
    let store = Store::new(redis_url.clone());
    let subs = subscribers::Subscribers::new();
    let ops = ops::OperationStore::new();
    let sse = ops::Broadcasters::new();

    rocket::build()
        .configure(rocket::Config {
            address: "0.0.0.0".parse().expect("valid IP address"),
            port: 8000,
            ..rocket::Config::default()
        })
        .manage(AppState {
            redis_url,
            config: app_config,
            subs,
            ops,
            sse,
        })
        .manage(Mutex::new(store))
        .mount(
            "/",
            openapi_get_routes![
                handlers::ip::borrow,
                handlers::ip::return_item,
                handlers::ip::submit_item,
                handlers::ip::get_operation_status,
            ],
        )
        .mount(
            "/",
            routes![
                handlers::ip::stream_operation_events,
            ],
        )
        .mount(
            "/swagger-ui/",
            make_swagger_ui(&SwaggerUIConfig {
                url: "../openapi.json".to_owned(),
                ..Default::default()
            }),
        )
        .mount(
            "/rapidoc/",
            make_rapidoc(&RapiDocConfig {
                general: GeneralConfig {
                    spec_urls: vec![UrlObject::new("General", "../openapi.json")],
                    ..Default::default()
                },
                hide_show: HideShowConfig {
                    allow_spec_url_load: false,
                    allow_spec_file_load: false,
                    ..Default::default()
                },
                ..Default::default()
            }),
        )
}
