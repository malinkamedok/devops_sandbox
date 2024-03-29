import argparse
import json
import sys

def deep_compare(obj1, obj2, threshold=0.05):
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
    parser.add_argument('answer', type=str, help='Path to the first JSON file')
    parser.add_argument('student', type=str, help='Path to the second JSON file')
    args = parser.parse_args()
    try:
        with open(args.answer, 'r', encoding='utf-8') as file1, open(args.student, 'r', encoding='utf-8') as file2:
            answer = json.load(file1)
            student = json.load(file2)
    except FileNotFoundError:
        print("One or both JSON files were not found.")
        sys.exit(1)

    if deep_compare(answer, student):
        print("The JSON files are deeply equal.")
    else:
        print("The JSON files are NOT deeply equal.")
        sys.exit(1)


if __name__ == "__main__":
    main()
