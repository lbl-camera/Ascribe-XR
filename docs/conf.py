# Configuration file for the Sphinx documentation builder.
#
# For the full list of built-in configuration values, see the documentation:
# https://www.sphinx-doc.org/en/master/usage/configuration.html

# -- Project information -----------------------------------------------------
project = "Ascribe XR"
copyright = "2025, The Regents of the University of California, through Lawrence Berkeley National Laboratory"
author = "ALS / LBNL Camera Team"

# -- General configuration ---------------------------------------------------
extensions = [
    "myst_parser",  # Markdown support
    "sphinx.ext.intersphinx",  # Link to other projects' documentation
    "sphinx_immaterial",  # Material theme extensions
]

templates_path = ["_templates"]
exclude_patterns = ["_build", "Thumbs.db", ".DS_Store", "superpowers"]

# Suppress warnings that are unavoidable in CI or in narrative docs
suppress_warnings = [
    "toc.not_included",  # superpowers plan/spec docs aren't in a toctree
    "myst.header",  # non-consecutive headers in imported notes
    "misc.highlighting_failure",  # code blocks with approximate language tags
]

# Markdown configuration
myst_enable_extensions = [
    "colon_fence",  # ::: directives
    "deflist",  # Definition lists
    "fieldlist",  # Field lists
    "tasklist",  # Task lists with checkboxes
]

# The suffix(es) of source filenames
source_suffix = {
    ".rst": "restructuredtext",
    ".md": "markdown",
}

# -- Options for HTML output -------------------------------------------------
html_theme = "sphinx_immaterial"
html_static_path = ["_static"]
html_title = "Ascribe XR Documentation"

# Theme options for sphinx-immaterial
html_theme_options = {
    "icon": {
        "repo": "fontawesome/brands/github",
    },
    "site_url": "https://lbl-camera.github.io/Ascribe-XR/",
    "repo_url": "https://github.com/lbl-camera/Ascribe-XR",
    "repo_name": "Ascribe-XR",
    "edit_uri": "blob/master/docs",
    "globaltoc_collapse": True,
    "features": [
        "navigation.expand",
        "navigation.sections",
        "navigation.top",
        "search.highlight",
        "search.share",
        "toc.follow",
        "toc.sticky",
        "content.tabs.link",
        "announce.dismiss",
    ],
    "palette": [
        {
            "media": "(prefers-color-scheme: light)",
            "scheme": "default",
            "primary": "deep-purple",
            "accent": "purple",
            "toggle": {
                "icon": "material/brightness-7",
                "name": "Switch to dark mode",
            },
        },
        {
            "media": "(prefers-color-scheme: dark)",
            "scheme": "slate",
            "primary": "deep-purple",
            "accent": "purple",
            "toggle": {
                "icon": "material/brightness-4",
                "name": "Switch to light mode",
            },
        },
    ],
    "toc_title_is_page_title": True,
}

# -- Intersphinx configuration -----------------------------------------------
intersphinx_mapping = {
    "python": ("https://docs.python.org/3", None),
}
intersphinx_timeout = 5  # seconds; don't stall the build if upstream is unreachable
