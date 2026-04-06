#!/bin/bash

source table.sh

DB_ROOT="./databases"

mkdir -p "$DB_ROOT"

function main_menu() {
    while true; do
        echo "************* Main Menu ****************"
        echo "1. Create and Connect to Database"
        echo "2. List Databases"
        echo "3. Connect to Database"
        echo "4. Drop Database"
        echo "5. Exit"

        read -p "Choose an option: " choice
        case $choice in
            1) create_database ;;
            2) list_databases ;;
            3) connect_database ;;
            4) drop_database ;;
            5) exit 0 ;;
            *) echo "Invalid option, please try again." ;;
        esac
    done
}

function create_database() {
    read -p "Enter database name: " db_name
    db_name="$(echo "$db_name" | xargs)"

    if ! validate_entity_name "$db_name"; then
        return
    fi

    if [ -d "$DB_ROOT/$db_name" ]; then
        echo "Database already exists."
        connect_database "$db_name"
    else
        mkdir "$DB_ROOT/$db_name"
        echo "Database '$db_name' created successfully."
        connect_database "$db_name"
    fi
}

function list_databases() {
    echo "Available Databases:"
    ls "$DB_ROOT"
}

function connect_database() {
    local db_name="$1"
    while true; do
        if [[ -z "$db_name" ]]; then
            read -p "Enter database name to connect (or :back to return): " db_name
            db_name="$(echo "$db_name" | xargs)"
        fi

        if [[ "$db_name" == ":back" ]]; then
            return
        fi

        if ! validate_entity_name "$db_name"; then
            db_name=""
            continue
        fi

        if [ -d "$DB_ROOT/$db_name" ]; then
            current_db="$DB_ROOT/$db_name"
            echo "Connected to database '$db_name'."
            table_menu
            return
        fi

        echo "Database does not exist. Try again or type :back to return."
    done
}

function drop_database() {
    read -p "Enter database name to drop: " db_name
    db_name="$(echo "$db_name" | xargs)"

    if ! validate_entity_name "$db_name"; then
        return
    fi

    if [ -d "$DB_ROOT/$db_name" ]; then
        if ! confirm_action "Are you sure you want to drop database '$db_name'?"; then
            echo "Drop database canceled."
            return
        fi
        rm -rf "$DB_ROOT/$db_name"
        echo "Database '$db_name' dropped successfully."
    else
        echo "Database does not exist."
    fi
}

main_menu