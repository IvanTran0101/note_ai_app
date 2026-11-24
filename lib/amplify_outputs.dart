const amplifyConfig = r'''{
  "auth": {
    "user_pool_id": "ap-southeast-1_9ymYSLiGJ",
    "aws_region": "ap-southeast-1",
    "user_pool_client_id": "65ivm4v617ruists4hvusaq954",
    "identity_pool_id": "ap-southeast-1:d6ad5a32-bbee-443f-9757-4ceb93ffa051",
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
    "syncApiEndpoint": "https://eu4ap50sx7.execute-api.ap-southeast-1.amazonaws.com",
    "attachmentApiEndpoint": "https://eu4ap50sx7.execute-api.ap-southeast-1.amazonaws.com",
    "attachmentProtocolVersion": 1,
    "aiApiEndpoint": "https://8q241n6o63.execute-api.ap-southeast-1.amazonaws.com",
    "ragApiEndpoint": "https://jsv55ime20.execute-api.ap-southeast-1.amazonaws.com",
    "eventHttpEndpoint": "https://x5mkm4svtzcjhg6hpjuct56ctu.appsync-api.ap-southeast-1.amazonaws.com/event",
    "eventSocketEndpoint": "wss://x5mkm4svtzcjhg6hpjuct56ctu.appsync-realtime-api.ap-southeast-1.amazonaws.com/event/realtime"
  }
}''';