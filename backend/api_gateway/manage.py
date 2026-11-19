#!/usr/bin/env python
"""API Gateway (:8000) — cổng vào duy nhất của Frontend tới 5 service."""
import os
import sys


def main():
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
    from django.core.management import execute_from_command_line
    execute_from_command_line(sys.argv)


if __name__ == '__main__':
    main()
