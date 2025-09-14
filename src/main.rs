#[macro_use]
extern crate rocket;

use dotenv::dotenv;

use crate::store::Store;

use rocket_okapi::settings::UrlObject;
use rocket_okapi::swagger_ui::make_swagger_ui;
use rocket_okapi::{openapi_get_routes, rapidoc::*, swagger_ui::*};

use std::env;
use tokio::sync::Mutex;

mod error;
mod handlers;
mod store;
mod guards;
mod config;
mod subscribers;
mod ops;

pub struct AppState {
    redis_url: String,
    config: config::AppConfig,
    subs: subscribers::Subscribers,
    ops: ops::OperationStore,
    sse: ops::Broadcasters,
}

#[rocket::main]
async fn main() {
    dotenv().ok();
    let args: Vec<String> = env::args().collect();
    if args.contains(&"--print-openapi".to_string()) {
        let settings = rocket_okapi::settings::OpenApiSettings::new();
        let spec = rocket_okapi::openapi_spec![
            handlers::ip::borrow_ip,
            handlers::ip::return_ip,
            handlers::ip::list_ips,
            handlers::ip::get_operation_status,
        ](&settings);
        println!("{}", serde_json::to_string_pretty(&spec).unwrap());
        return;
    }

    let redis_url = env::var("REDIS_URL").unwrap_or_else(|_| "redis://127.0.0.1/".to_string());

    // Load config from optional --config <path>
    let mut args_iter = args.iter();
    let mut app_config = config::AppConfig::default();
    while let Some(arg) = args_iter.next() {
        if arg == "--config" {
            if let Some(path) = args_iter.next() {
                let path = std::path::Path::new(path);
                match config::AppConfig::from_path(path) {
                    Ok(cfg) => app_config = cfg,
                    Err(e) => {
                        eprintln!("Failed to load config from {}: {}", path.display(), e);
                        std::process::exit(2);
                    }
                }
            }
        }
    }

    let store = Store::new(redis_url.clone());
    let subs = subscribers::Subscribers::new();
    let ops = ops::OperationStore::new();
    let sse = ops::Broadcasters::new();

    let _ = rocket::build()
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
                handlers::ip::borrow_ip,
                handlers::ip::return_ip,
                handlers::ip::list_ips,
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
        .launch()
        .await;
}