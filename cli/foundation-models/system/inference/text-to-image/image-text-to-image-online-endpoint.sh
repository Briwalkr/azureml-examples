set -x
# the commands in this file map to steps in this notebook: https://aka.ms/azureml-infer-batch-sdk-text-classification

# script inputs
registry_name="azureml"

subscription_id="<SUBSCRIPTION_ID>"
resource_group_name="<RESOURCE_GROUP>"
workspace_name="<WORKSPACE_NAME>"

# This is the model from system registry that needs to be deployed
model_name="stabilityai-stable-diffusion-xl-refiner-1-0"
model_label="latest"
response_file="generated_image.json"

version=$(date +%s)
endpoint_name="image-text-to-image-$version"
deployment_name="image-text-to-image-deploy"

deployment_sku="Standard_NC6s_v3"

# sample_request_data
sample_request_data="inpainting_data/sample_request_data.json"

# 1. Setup pre-requisites
if [ "$subscription_id" = "<SUBSCRIPTION_ID>" ] || \
   ["$resource_group_name" = "<RESOURCE_GROUP>" ] || \
   [ "$workspace_name" = "<WORKSPACE_NAME>" ]; then 
    echo "Please update the script with the subscription_id, resource_group_name and workspace_name"
    exit 1
fi

az account set -s $subscription_id
workspace_info="--resource-group $resource_group_name --workspace-name $workspace_name"

# 2. Check if the model exists in the registry

if ! az ml model show --name $model_name --label $model_label --registry-name $registry_name
then
    echo "Model $model_name:$model_label does not exist in registry $registry_name"
    exit 1
fi

# Get the latest model version
model_version=$(az ml model show --name $model_name --label $model_label --registry-name $registry_name --query version --output tsv)

# 3. Deploy the model to an endpoint
# Create online endpoint 
az ml online-endpoint create --name $endpoint_name $workspace_info  || {
    echo "endpoint create failed"; exit 1;
}

# Deploy model from registry to endpoint in workspace
az ml online-deployment create --file deploy-online.yaml $workspace_info --all-traffic --set \
  endpoint_name=$endpoint_name model=azureml://registries/$registry_name/models/$model_name/versions/$model_version \
  name=$deployment_name \
  instance_type=$deployment_sku || {
    echo "deployment create failed"; exit 1;
}

# 4. Submit a sample request to endpoint
python utils/prepare_data_image_text_to_image.py --payload-path $sample_request_data --mode "online"

# Check if scoring data file exists
if [ -f $sample_request_data ]; then
    echo "Invoking endpoint $endpoint_name with $sample_request_data:\n\n"
    echo "\n\n"
else
    echo "Request file $sample_request_data does not exist"
    exit 1
fi

az ml online-endpoint invoke --name $endpoint_name --request-file $sample_request_data $workspace_info  -o json > $response_file || {
    echo "endpoint invoke failed"; exit 1;
}

# 5. Convert bas64 form of image to jpeg
python ./utils/base64_to_jpeg.py --response_file $response_file

# 6. Delete the endpoint and sample_request_data.json
az ml online-endpoint delete --name $endpoint_name $workspace_info --yes || {
    echo "endpoint delete failed"; exit 1;
}