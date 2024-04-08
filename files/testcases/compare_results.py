import argparse
import json
import sys

def is_valid_json(file_path: str) -> bool:
    try:
        with open(file_path, 'r') as file:
            json.load(file)
        return True
    except json.JSONDecodeError:
        return False

def deep_compare(obj1: dict, obj2: dict, threshold=0.5) -> bool:
    """
    Args:
        obj1 (dict): answer json
        obj2 (dict): student json
        threshold (float, optional): For avoiding accuracy problems. Defaults to 0.5.

    Returns:
        bool: are two json objects deeply equal?
    """
    if isinstance(obj1, dict) and isinstance(obj2, dict):
        if len(obj1) != len(obj2):
            return False
        for key in obj1:
            if key not in obj2 or not deep_compare(obj1[key], obj2[key], threshold):
                return False
        return True
    elif isinstance(obj1, list) and isinstance(obj2, list):
        if len(obj1) != len(obj2):
            return False
        for i in range(len(obj1)):
            if not deep_compare(obj1[i], obj2[i], threshold):
                return False
        return True
    elif isinstance(obj1, (int, float)) and isinstance(obj2, (int, float)):
        return abs(obj1 - obj2) <= max(abs(obj1), abs(obj2)) * threshold
    else:
        return obj1 == obj2

def main():
    parser = argparse.ArgumentParser(description='Compare two JSON files deeply with a threshold for numbers.')
    parser.add_argument('service_type', type=str, help='Service type (currency ot weather)')
    parser.add_argument('answer', type=str, help='Path to the first JSON file')
    parser.add_argument('student', type=str, help='Path to the second JSON file')
    args = parser.parse_args()
    try:
        if not is_valid_json(args.student):
            print("Response is not a valid JSON")
            exit(1)
        with open(args.answer, 'r', encoding='utf-8') as file1, open(args.student, 'r', encoding='utf-8') as file2:
            answer = json.load(file1)
            student = json.load(file2)
    except FileNotFoundError:
        print("One or both JSON files were not found.")
        sys.exit(1)

    if student is not None and "data" not in student:
        print("Response should contain 'data' key")
        sys.exit(1)

    if deep_compare(answer["data"], student["data"]):
        print("The JSON files are deeply equal.")
    else:
        print(args.service_type)
        # print("The JSON files are NOT deeply equal.")
        sys.exit(1)


if __name__ == "__main__":
    main()
