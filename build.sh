#!/bin/bash
clear

required_packages=(git flex bison gperf build-essential zip curl libc6-dev libncurses-dev libx11-dev \
    libreadline-dev libgl1 libgl1-mesa-dev python3 make bc grep tofrodos python3-markdown \
    libxml2-utils xsltproc zlib1g-dev libc6-dev libtinfo6 make repo cpio kmod openssl \
    libelf-dev pahole libssl-dev)

install_required_tools() {
    missing_packages=()
    for package in "${required_packages[@]}"; do
        if ! dpkg -l | grep -q "$package"; then
            missing_packages+=("$package")
        fi
    done
    if [ ${#missing_packages[@]} -eq 0 ]; then
        echo "All required packages are already installed."
    else
        echo "Missing packages: ${missing_packages[*]}"
        read -p "Do you want to install them? (y/n) " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            sudo apt install -y "${missing_packages[@]}"
        else
            echo "Please install the required packages manually."
        fi
    fi
    sleep 2
    main_menu
}

checkup_tools() {
    echo "Checking required packages..."
    missing_packages=()
    for package in "${required_packages[@]}"; do
        if ! dpkg -l | grep -q "$package"; then
            missing_packages+=("$package")
        fi
    done
    if [ ${#missing_packages[@]} -eq 0 ]; then
        echo "All required packages are installed."
    else
        echo "Missing packages: ${missing_packages[*]}"
    fi

    echo "Checking Git submodules..."
    if git submodule status 2>/dev/null | grep -q '^-'; then
        echo "Some Git submodules are missing or not initialized."
    else
        echo "All Git submodules are properly initialized."
    fi
    sleep 3
    main_menu
}

setup_telegram() {
    read -p "Do you want to send the built kernel on Telegram after it get built? (y/n) " use_tg
    if [[ "$use_tg" =~ ^[Yy]$ ]]; then
        if [[ -f ".tg_chat" ]]; then
            TG_CHAT=$(cat .tg_chat)
        else
            read -p "Enter your Telegram chat ID: " TG_CHAT
            echo "$TG_CHAT" > .tg_chat
        fi

        if [[ -f ".tg_bot_http" ]]; then
            TG_BOT_HTTP=$(cat .tg_bot_http)
        else
            read -p "Enter your Telegram bot HTTP API URL: " TG_BOT_HTTP
            echo "$TG_BOT_HTTP" > .tg_bot_http
        fi
    else
        TG_CHAT=""
        TG_BOT_HTTP=""
    fi
}

send_to_telegram() {
    local file_path="$1"
    if [[ -n "$TG_CHAT" && -n "$TG_BOT_HTTP" && -f "$file_path" ]]; then
        echo "Sending $file_path to Telegram..."
        curl -s "https://api.telegram.org/bot$TG_BOT_HTTP/sendDocument" \
        -F parse_mode=markdown \
        -F chat_id=$TG_CHAT \
        -F document=@$file_path \
        -F "Kernel built successfully!"
        echo "File sent successfully!"
    else
        echo "Skipping Telegram upload. No credentials set."
    fi
}

display_system_info() {
    clear
    echo "===================================================="
    echo "                     PRIT BUILDER                 "
    echo "===================================================="
    echo "================ System Information ================"
    echo "Free Storage: $(df -h / | awk 'NR==2 {print $4}')"
    echo "Free RAM: $(free -h | awk 'NR==2 {print $7}')"
    echo "CPU Cores: $(nproc)"
    echo "===================================================="
    echo ""
}

main_menu() {
    while true; do
        display_system_info
        echo "1) Build Kernel"
        echo "2) Clean Kernel Source"
        echo "3) Install Required Tools"
        echo "4) Checkup Tools"
        echo "5) Exit"
        echo ""
        read -p "Choose an option: " choice

        case $choice in
            1) build_kernel; break ;;
            2) clean_kernel_source; break ;;
            3) install_required_tools; break ;;
            4) checkup_tools; break ;;
            5) echo "Exiting..."; exit 0 ;;
            *) echo "Invalid choice! Please select a valid option." ;;
        esac
    done
}

clean_kernel_source() {
    echo "Cleaning kernel source..."
    rm -rf out/
    make clean
    echo "Kernel source cleaned!"
    sleep 2
    main_menu
}

build_kernel() {
    read -p "Enter the username for whom the kernel is being built: " KBUILD_BUILDUSER
    read -p "Enter the number of cores to use for the build: " num_cores

    if ! [[ "$num_cores" =~ ^[0-9]+$ ]]; then
        echo "Invalid number of cores! Please enter a valid number."
        exit 1
    fi

    export ARCH=arm64
    export PATH="$(pwd)/toolchains/aarch64-linux-android-4.9/bin:$PATH"
    export KBUILD_BUILDUSER
    export KBUILD_BUILDHOST=prit

    echo "Starting kernel build..."
    make O=out ARCH=arm64 oppo6765_18511_defconfig
    make O=out ARCH=arm64 -j"$num_cores"

    IMAGE_PATH_GZ="out/arch/arm64/boot/Image.gz"
    IMAGE_PATH="out/arch/arm64/boot/Image"

    if [[ -f "$IMAGE_PATH_GZ" ]]; then
        echo "Kernel build succeeded! Found Image.gz"
        send_to_telegram "$IMAGE_PATH_GZ"
    elif [[ -f "$IMAGE_PATH" ]]; then
        echo "Kernel build succeeded! Found Image"
        send_to_telegram "$IMAGE_PATH"
    else
        echo "Kernel build failed! Neither Image.gz nor Image was found."
        exit 1
    fi
}

setup_telegram
main_menu
