#!/bin/bash
CLOUD_REGION=us-central1

# color variables
RED='\033[0;31m'
BLU='\033[0;34m'
GRN='\033[0;32m'
PUR='\033[0;35m'
NC='\033[0m'

showspin()
{
  local i sp n
  sp='⣾⣽⣻⢿⡿⣟⣯⣷'
  n=${#sp}
  tput civis
  trap 'tput cnorm' EXIT
  while sleep 0.1; do
      printf "${sp:i++%n:1}\b"
  done
}

printf "\n${BLU}***********************************************\n\n"
printf "Welcome to the PIC-IoT interactive quick setup\n\n"
printf "***********************************************${NC}\n\n" 

printf "${GRN}To set up your Firebase credentials for this project\n"
printf "copy the URL below and paste into a new browser tab.\n"
printf "Then, copy and paste the authorization code into this terminal.${NC}\n\n"

# log in to firebase
firebase login --no-localhost

# get device name, project name and device public key from user
echo 
read -p 'Please enter device UID: ' DEVICE_ID
echo

# let user choose to set IoT core registry name
REG_NAME=""
ATTEMPT=0
# check that REG_NAME matches pattern
while ! [[ $REG_NAME =~ ^[a-zA-Z]{1}[a-zA-Z0-9+%~._-]{2,254} ]]
do

# display hint if user has made 1 or more attempt
if (( ATTEMPT > 0 )); then
printf "\n${RED}IoT Core Registry names must be between 3-255 characters,\nstart with a letter, and contain only letters, numbers and\n the following characters:\n"
echo '- . % ~ +'
echo
printf "${NC}"
fi 

# get user REG_NAME input
read -p 'Choose an IoT Core registry name (return for PIC-IOT): ' REG_NAME
ATTEMPT=$((ATTEMPT + 1))

# set to default if no text entered
if [ "$REG_NAME" = "" ]; then
  REG_NAME="PIC-IOT"
fi

# strip white space
REG_NAME="$(echo "${REG_NAME}" | tr -d '[:space:]')"
done

# set the project and tell firebase to use it firebase
printf "\n${BLU}Creating Firebase web app ${REG_NAME}\n${NC}"
gcloud config set project $GOOGLE_CLOUD_PROJECT
firebase use $GOOGLE_CLOUD_PROJECT
firebase apps:create web microchip-dev-board-app > app.txt
GET_CONFIG=$(tail -1 app.txt)

# enable cloud functions, IoT core, and pub sub
printf "\n${BLU}Enabling cloud functions... ${NC}"
gcloud services enable cloudfunctions.googleapis.com cloudiot.googleapis.com pubsub.googleapis.com > /dev/null 2>&1
printf "${BLU}DONE. \n${NC}"

# create pubsub topic
printf "\n${BLU}Creating pubsub topic... ${NC}"
gcloud pubsub topics create pic-iot > /dev/null 2>&1
printf "${BLU}DONE. \n${NC}"

printf "\n${BLU}Creating IoT core registry ${REG_NAME}...\n${NC}"
# create IoT core device registry
gcloud iot registries create $REG_NAME --region=$CLOUD_REGION --event-notification-config=topic=pic-iot

# add device to registry
printf "\n${BLU}Adding device d${DEVICE_ID} to registry... \n${NC}"
gcloud iot devices create "d$DEVICE_ID" --region=$CLOUD_REGION --registry=$REG_NAME

#install npm dependencies
printf "\n${BLU}Installing Cloud Function dependencies (this may take a few minutes)...${NC}"
showspin &
spin_pid=$!
npm install --prefix ./functions/ > /dev/null 2>&1
kill $spin_pid &>/dev/null
printf "${BLU}DONE.\n${NC}"
printf "\n${BLU}Installing UI dependencies (this may take a few minutes)...${NC}"
showspin &
spin_pid=$!
npm install --prefix ./ui/ > /dev/null 2>&1
kill $spin_pid &>/dev/null
printf "${BLU}DONE.\n${NC}"

# retrieve UI config vars
eval $GET_CONFIG > config.txt
node getFirebaseConfig.js config.txt

# cleanup ephemera
rm config.txt app.txt

# build UI
printf "\n${BLU}Creating a production build of the UI (this may take a few minutes)...${NC}"
showspin &
spin_pid=$!
npm run build --prefix ./ui > /dev/null 2>&1
kill $spin_pid &>/dev/null
printf "${BLU}DONE.\n${NC}"

chmod +x ./ui/src/Config.js

printf "${BLU}Deploying UI (this may take a few minutes)...\n${NC}"
firebase deploy --only functions:recordMessage
firebase deploy --only database
firebase deploy --only hosting

printf "\n${GRN}**************************************\n\n" 
printf "Setup complete!\n\n"
printf "${PUR}Remember to add your device\'s public key in the registry:\n\n"
printf "https://console.cloud.google.com/iot/registries\n\n"
printf "${GRN}Once you\'ve added the public key, checkout your app:\n\n"
printf "https://${GOOGLE_CLOUD_PROJECT}.firebaseapp.com/device/${DEVICE_ID}\n\n"
printf "**************************************\n\n${NC}" 
