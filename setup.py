"""Setup file for skill-to-sandbox pipeline package."""

from setuptools import setup, find_packages

setup(
    name="skill-to-sandbox",
    version="0.1.0",
    description="Pipeline to convert skill/subagent definitions into sandbox environments",
    packages=find_packages(),
    python_requires=">=3.11",
    install_requires=[
        # Core dependencies are optional for now
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
        ],
    },
)
