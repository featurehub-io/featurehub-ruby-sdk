
# configure FeatureHub. Mostly taken from the rails portion of this doc:
# https://github.com/featurehub-io/featurehub-ruby-sdk/tree/main#2-create-featurehub-config
Rails.configuration.fh_config = FeatureHub::Sdk::FeatureHubConfig.new(
    # you may have to change this URL in your app. Assuming you're running the party server locally 
    # (i.e. what's described here https://www.featurehub.io/) to test out FeatureHub you can find this URL by running
    # docker ps and finding the container with an image name like 'featurehub/party-server:latest'
    # running via docker? use this URL:
    # "http://host.docker.internal:8085/",
    "http://0.0.0.0:8085/",
    # You can find this value in the admin console by navigating to the 'API Keys' section of the UI and choosing
    # between the client and the server API Keys for whatever service account you've set up. Learn more about the
    # differences between client-side evaluation here:
    # https://docs.featurehub.io/featurehub/latest/sdks-development.html#_client_side_evaluation
    # and server-side evaluation here:
    # https://docs.featurehub.io/featurehub/latest/sdks-development.html#_supporting_server_side_evaluation 
    ["TODO_CHANGE_ME"],
).init