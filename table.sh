#!/bin/bash

function confirm_action() {
    local prompt="$1"

    while true; do
        read -p "$prompt (y/n): " answer
        case "${answer,,}" in
            y|yes)
                return 0
                ;;
            n|no)
                return 1
                ;;
            *)
                echo "Please answer with y or n."
                ;;
        esac
    done
}

function validate_entity_name() {
    local name
    name="$(echo "$1" | xargs)"

    if [[ -z "$name" ]]; then
        echo "Name cannot be empty."
        return 1
    fi

    if [[ ! "$name" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
        echo "Invalid name. It must start with a letter and contain only letters, numbers, or underscore (_)."
        return 1
    fi

    return 0
}

function table_menu() {
    while true; do
        echo "************* Table Menu ****************"
        echo "1. Create Table"
        echo "2. List Tables"
        echo "3. Drop Table"
        echo "4. Insert Record"
        echo "5. Select Records"
        echo "6. Delete Record"
        echo "7. Update Record"
        echo "8. Back to Main Menu"

        read -p "Choose an option: " choice

        case $choice in
            1) create_table ;;
            2) list_tables ;;
            3) drop_table ;;
            4) insert_record ;;
            5) select_records ;;
            6) delete_record ;;
            7) update_record ;;
            8) break ;;
            *) echo "Invalid option, please try again." ;;
        esac
    done
}

function validate_value_by_type() {
    local value="$1"
    local col_type="$2"

    [[ -z "$value" ]] && return 1
    # Remove leading/trailing whitespace
    value="$(echo "$value" | xargs)"

    case "$col_type" in
        int)
            [[ "$value" =~ ^-?[0-9]+$ ]]
            ;;
        float)
            [[ "$value" =~ ^-?([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]]
            ;;
        string)
            return 0
            ;;
        bool|boolean)
            local lower_value="${value,,}"
            [[ "$lower_value" =~ ^(true|false|1|0)$ ]]
            ;;
        *)
            return 1
            ;;
    esac
}

function create_table() {
    read -p "Enter table name: " table_name
    table_name="$(echo "$table_name" | xargs)"

    if ! validate_entity_name "$table_name"; then
        return
    fi

    meta_file="$current_db/$table_name.meta"
    data_file="$current_db/$table_name.data"

    if [ -f "$meta_file" ]; then
        echo "Table already exists."
        return
    fi

    read -p "Enter Number of columns: " num_cols

    > "$meta_file" # Create meta file and clear if exists
    has_primary_key=0

    for ((i=1; i<=num_cols; i++)); do
        read -p "Enter column $i name: " col_name
        col_name="$(echo "$col_name" | xargs)"

        if ! validate_entity_name "$col_name"; then
            return
        fi

        read -p "Enter column $i type (string/int/float/bool): " col_type
        col_type=$(echo "$col_type" | tr '[:upper:]' '[:lower:]')

        if [[ "$col_type" == "boolean" ]]; then
            col_type="bool"
        fi

        if [[ "$col_type" != "string" && "$col_type" != "int" && "$col_type" != "float" && "$col_type" != "bool" ]]; then
            echo "Invalid column type. Please enter 'string', 'int', 'float', or 'bool'."
            return
        fi

        if [[ "$has_primary_key" -eq 0 ]]; then
            read -p "Is this column a primary key? (y/n): " is_pk
            if [[ "$is_pk" == "y" ]]; then
                col_type="$col_type:pk"
                has_primary_key=1
            fi
        fi

        echo "$col_name:$col_type" >> "$meta_file"
    done

    touch "$data_file" # Create data file
    echo "Table '$table_name' created successfully."
    if [[ $has_primary_key -eq 1 ]]; then
        echo "Note: Primary key values must be UNIQUE and NOT NULL (cannot be empty)."
    fi
}

function list_tables() {
    echo "Available Tables:"
    ls "$current_db" | grep -E '\.meta$' | sed 's/\.meta$//'
}

function drop_table() {
    read -p "Enter table name to drop: " table_name
    table_name="$(echo "$table_name" | xargs)"

    if ! validate_entity_name "$table_name"; then
        return
    fi

    meta_file="$current_db/$table_name.meta"
    data_file="$current_db/$table_name.data"

    if [ -f "$meta_file" ]; then
        if ! confirm_action "Are you sure you want to drop table '$table_name'?"; then
            echo "Drop table canceled."
            return
        fi
        rm -f "$meta_file" "$data_file"
        echo "Table '$table_name' dropped successfully."
    else
        echo "Table does not exist."
    fi
}


function insert_record() {
    read -p "Enter table name to insert into: " table_name
    table_name="$(echo "$table_name" | xargs)"

    if ! validate_entity_name "$table_name"; then
        return
    fi

    meta_file="$current_db/$table_name.meta"
    data_file="$current_db/$table_name.data"

    if [ ! -f "$meta_file" ]; then
        echo "Table does not exist."
        return
    fi

    while true; do
        record_values=()
        pk_col_index=-1
        col_index=0

        exec 3< "$meta_file"
        while IFS= read -r line <&3; do
            col_name=$(echo "$line" | cut -d: -f1)
            col_type=$(echo "$line" | cut -d: -f2-)
            base_col_type=${col_type%%:*}

            while true; do
                read -p "Enter value for $col_name ($base_col_type) [or :back to cancel]: " value

                if [[ "$value" == ":back" ]]; then
                    exec 3<&-
                    echo "Insert canceled."
                    return
                fi

                if validate_value_by_type "$value" "$base_col_type"; then
                    break
                fi

                if [[ "$col_type" == *:pk ]]; then
                    echo "Primary key cannot be empty and must be $base_col_type."
                elif [[ "$base_col_type" == "int" ]]; then
                    echo "Invalid input. Expected an integer."
                elif [[ "$base_col_type" == "float" ]]; then
                    echo "Invalid input. Expected a float."
                elif [[ "$base_col_type" == "bool" || "$base_col_type" == "boolean" ]]; then
                    echo "Invalid input. Expected a boolean (true/false/1/0)."
                else
                    echo "Invalid input for type '$base_col_type'."
                fi
            done

            if [[ "$col_type" == *:pk ]]; then
                pk_col_index=$col_index
            fi

            record_values+=("$value")
            ((col_index++))
        done
        exec 3<&-

        # Enforce primary key uniqueness constraint
        if [[ "$pk_col_index" -ge 0 ]]; then
            pk_value="${record_values[$pk_col_index]}"
            if awk -F'|' -v pk_index=$((pk_col_index+1)) -v pk_value="$pk_value" \
             '$pk_index == pk_value { found=1; exit } END { exit !found }' "$data_file"; then
                echo "Error: Primary key value '$pk_value' already exists. Record not inserted."
                continue
            fi
        fi

        record=""
        for value in "${record_values[@]}"; do
            record+="$value|"
        done

        record=${record%|}  # Remove trailing|

        echo "$record" >> "$data_file"
        echo "Record inserted successfully."

        read -p "Do you want to insert another record in the same table? (y/n): " insert_another
        if [[ ! "$insert_another" =~ ^[Yy]$ ]]; then
            break
        fi
    done
}

function select_records() {
    read -p "Enter table name to select from: " table_name
    table_name="$(echo "$table_name" | xargs)"

    if ! validate_entity_name "$table_name"; then
        return
    fi

    meta_file="$current_db/$table_name.meta"
    data_file="$current_db/$table_name.data"

    if [ ! -f "$meta_file" ]; then
        echo "Table does not exist."
        return
    fi

    if [ ! -s "$data_file" ]; then
        echo "No records found."
        return
    fi

    # Print column headers
    headers=""
    while IFS= read -r line; do
        col_name=$(echo "$line" | cut -d: -f1)
        headers+="$col_name | "
    done < "$meta_file"
    headers=${headers% | } # Remove trailing |
    echo "$headers"
    echo "-------------------------"

    # Print records
    while IFS= read -r record; do
        echo "$record" | tr '|' ' '
    done < "$data_file"
}


function delete_record() {
    read -p "Enter table name to delete from: " table_name
    table_name="$(echo "$table_name" | xargs)"

    if ! validate_entity_name "$table_name"; then
        return
    fi

    meta_file="$current_db/$table_name.meta"
    data_file="$current_db/$table_name.data"

    if [ ! -f "$meta_file" ]; then
        echo "Table does not exist."
        return
    fi

    if [ ! -s "$data_file" ]; then
        echo "No records found."
        return
    fi

    read -p "Enter primary key value to delete: " pk_value

    # Get PK column index
    pk_col_index=-1
    i=0
    while IFS= read -r line; do
        col_type=$(echo "$line" | cut -d: -f2-)
        if [[ "$col_type" == *:pk ]]; then
            pk_col_index=$i
            break
        fi
        ((i++))
    done < "$meta_file"

    if [ $pk_col_index -eq -1 ]; then
        echo "No primary key defined for this table."
        return
    fi

    target_line_number=$(awk -F'|' -v pk_index=$((pk_col_index+1)) -v pk_value="$pk_value" '$pk_index == pk_value { print NR; exit }' "$data_file")

    if [[ -z "$target_line_number" ]]; then
        echo "No record found with that primary key."
        return
    fi

    if ! confirm_action "Are you sure you want to delete record with primary key '$pk_value' from table '$table_name'?"; then
        echo "Delete record canceled."
        return
    fi

    # Delete record with matching PK value
    awk -F'|' -v pk_index=$((pk_col_index+1)) -v pk_value="$pk_value" '$pk_index != pk_value' "$data_file" > "$data_file.tmp" && mv "$data_file.tmp" "$data_file"
    echo "Record deleted successfully."
}


function update_record() {
    read -p "Enter table name to update: " table_name
    table_name="$(echo "$table_name" | xargs)"

    if ! validate_entity_name "$table_name"; then
        return
    fi

    meta_file="$current_db/$table_name.meta"
    data_file="$current_db/$table_name.data"

    if [ ! -f "$meta_file" ]; then
        echo "Table does not exist."
        return
    fi

    if [ ! -s "$data_file" ]; then
        echo "No records found."
        return
    fi

    # Get column metadata and PK index
    pk_col_index=-1
    col_names=()
    col_types=()
    i=0
    while IFS= read -r line; do
        col_name=$(echo "$line" | cut -d: -f1)
        col_type=$(echo "$line" | cut -d: -f2-)
        base_col_type=${col_type%%:*}
        col_names+=("$col_name")
        col_types+=("$base_col_type")
        if [[ "$col_type" == *:pk ]]; then
            pk_col_index=$i
        fi
        ((i++))
    done < "$meta_file"

    if [ $pk_col_index -eq -1 ]; then
        echo "No primary key defined for this table."
        return
    fi

    pk_col_type="${col_types[$pk_col_index]}"

    while true; do
        read -p "Enter primary key value of the row to update (or :back to cancel): " pk_value

        if [[ "$pk_value" == ":back" ]]; then
            echo "Update canceled."
            return
        fi

        if ! validate_value_by_type "$pk_value" "$pk_col_type"; then
            echo "Error: Primary key cannot be empty and must be $pk_col_type."
            continue
        fi

        target_line_number=$(awk -F'|' -v pk_index=$((pk_col_index+1)) -v pk_value="$pk_value" '$pk_index == pk_value { print NR; exit }' "$data_file")
        if [[ -n "$target_line_number" ]]; then
            break
        fi

        echo "No record found with that primary key. Try again or type :back to cancel."
    done

    current_record=$(sed -n "${target_line_number}p" "$data_file")
    IFS='|' read -r -a record_values <<< "$current_record"

    echo "Choose a column to update:"
    for ((i=0; i<${#col_names[@]}; i++)); do
        col_label="${col_names[$i]} (${col_types[$i]})"
        if [[ $i -eq $pk_col_index ]]; then
            col_label+=" [PK]"
        fi
        echo "$((i+1)). $col_label"
    done

    while true; do
        read -p "Enter column number to update (or :back to cancel): " col_choice

        if [[ "$col_choice" == ":back" ]]; then
            echo "Update canceled."
            return
        fi

        if [[ "$col_choice" =~ ^[0-9]+$ ]] && [ "$col_choice" -ge 1 ] && [ "$col_choice" -le "${#col_names[@]}" ]; then
            selected_col_index=$((col_choice-1))
            break
        fi

        echo "Invalid column choice. Please enter a valid number."
    done

    selected_col_name="${col_names[$selected_col_index]}"
    selected_col_type="${col_types[$selected_col_index]}"
    selected_current_value="${record_values[$selected_col_index]}"

    while true; do
        read -p "Enter new value for $selected_col_name ($selected_col_type) [current: $selected_current_value, :back=cancel]: " new_value

        if [[ "$new_value" == ":back" ]]; then
            echo "Update canceled."
            return
        fi

        if ! validate_value_by_type "$new_value" "$selected_col_type"; then
            if [[ "$selected_col_type" == "int" ]]; then
                echo "Invalid input. Expected an integer."
            elif [[ "$selected_col_type" == "float" ]]; then
                echo "Invalid input. Expected a float."
            elif [[ "$selected_col_type" == "bool" || "$selected_col_type" == "boolean" ]]; then
                echo "Invalid input. Expected a boolean (true/false/1/0)."
            else
                echo "Invalid input for type '$selected_col_type'."
            fi
            continue
        fi

        # Enforce primary key uniqueness when updating PK column
        if [[ $selected_col_index -eq $pk_col_index ]]; then
            if awk -F'|' -v target="$target_line_number" -v pk_index=$((pk_col_index+1)) -v pk_value="$new_value" 'NR != target && $pk_index == pk_value { found=1; exit } END { exit !found }' "$data_file"; then
                echo "Error: Primary key value '$new_value' already exists. Please enter a different value."
                continue
            fi
        fi

        record_values[$selected_col_index]="$new_value"
        break
    done

    updated_record=""
    for value in "${record_values[@]}"; do
        updated_record+="$value|"
    done
    updated_record=${updated_record%|}

    awk -v target="$target_line_number" -v new_record="$updated_record" 'NR==target { $0=new_record } { print }' "$data_file" > "$data_file.tmp" && mv "$data_file.tmp" "$data_file"

    echo "Record updated successfully."
}