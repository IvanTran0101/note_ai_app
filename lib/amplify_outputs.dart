const amplifyConfig = r'''{
  "auth": {
    "user_pool_id": "ap-southeast-1_WnOTzVsLd",
    "aws_region": "ap-southeast-1",
    "user_pool_client_id": "6n4k7jpaoq6482aohl4grnondn",
    "identity_pool_id": "ap-southeast-1:2a7a181c-a10d-469f-af5c-24a6514fa167",
    "mfa_methods": [],
    "standard_required_attributes": [
      "email"
    ],
    "username_attributes": [
      "email"
    ],
    "user_verification_types": [
      "email"
    ],
    "groups": [],
    "mfa_configuration": "NONE",
    "password_policy": {
      "min_length": 8,
      "require_lowercase": true,
      "require_numbers": true,
      "require_symbols": true,
      "require_uppercase": true
    },
    "unauthenticated_identities_enabled": false
  },
  "version": "1.5",
  "custom": {
    "syncApiEndpoint": "https://gx25uupkri.execute-api.ap-southeast-1.amazonaws.com"
  }
}''';
