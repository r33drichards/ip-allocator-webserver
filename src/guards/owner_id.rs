use rocket::{Request, http::Status, outcome::Outcome};
use rocket::request::{self, FromRequest};
use rocket_okapi::gen::OpenApiGenerator;
use rocket_okapi::request::{OpenApiFromRequest, RequestHeaderInput};
use schemars::schema::{InstanceType, SingleOrVec};

/// Custom request guard that extracts the owner ID from the X-Owner-Id header.
/// This is used to identify who owns a borrowed item and enforce authorization.
pub struct OwnerId(pub String);

#[rocket::async_trait]
impl<'r> FromRequest<'r> for OwnerId {
    type Error = ();

    async fn from_request(request: &'r Request<'_>) -> request::Outcome<Self, Self::Error> {
        // Check if the 'X-Owner-Id' header is present
        if let Some(owner_id) = request.headers().get_one("X-Owner-Id") {
            Outcome::Success(OwnerId(owner_id.to_string()))
        } else {
            // Missing owner ID header - return 401 Unauthorized
            Outcome::Error((Status::Unauthorized, ()))
        }
    }
}

impl<'r> OpenApiFromRequest<'r> for OwnerId {
    fn from_request_input(
        _gen: &mut OpenApiGenerator,
        _name: String,
        _required: bool,
    ) -> rocket_okapi::Result<RequestHeaderInput> {
        Ok(RequestHeaderInput::Parameter(
            rocket_okapi::okapi::openapi3::Parameter {
                name: "X-Owner-Id".to_owned(),
                location: "header".to_owned(),
                description: Some("Owner identifier for authorization. Required for borrowing and returning items.".to_owned()),
                required: true,
                deprecated: false,
                allow_empty_value: false,
                value: rocket_okapi::okapi::openapi3::ParameterValue::Schema {
                    style: None,
                    explode: None,
                    allow_reserved: false,
                    schema: rocket_okapi::okapi::openapi3::SchemaObject {
                        instance_type: Some(SingleOrVec::Single(
                            Box::new(InstanceType::String)
                        )),
                        ..Default::default()
                    },
                    example: None,
                    examples: None,
                },
                extensions: Default::default(),
            }
        ))
    }
}
