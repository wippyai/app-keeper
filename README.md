<p align="center">
    <a href="https://wippy.ai" target="_blank">
        <picture>
            <source media="(prefers-color-scheme: dark)" srcset="https://github.com/wippyai/.github/blob/main/logo/wippy-text-dark.svg?raw=true">
            <img width="30%" align="center" src="https://github.com/wippyai/.github/blob/main/logo/wippy-text-light.svg?raw=true" alt="Wippy logo">
        </picture>
    </a>
</p>
<h1 align="center">Wippy Keeper</h1>
<div align="center">

[![Latest Release](https://img.shields.io/github/v/release/wippyai/app-keeper?style=for-the-badge)][releases-page]
[![License](https://img.shields.io/github/license/wippyai/app-keeper?style=for-the-badge)](LICENSE)
[![Documentation](https://img.shields.io/badge/documentation-0F6640.svg?style=for-the-badge&logo=gitbook)][wippy-documentation]

</div>

Wippy Keeper is the central management agent for the Wippy platform that coordinates all specialized system agents.
It serves as the main hub for users to access various system capabilities.

## Primary Responsibilities

1. Connect users with the right specialized agent for their task
2. Provide an overview of available system capabilities
3. Coordinate workflows that require multiple specialized agents
4. Maintain context when switching between agents

## Available Specialized Agents

- **Documentation Agent**: For accessing module specifications and technical documentation
- **Command Executor**: For executing system commands and processing output
- **Filesystem Manager**: For file and directory operations
- **Registry Manager**: For managing the distributed registry system
- **Views Manager**: For handling application presentation layer, views, templates, and resources
- **Coder**: For creating, updating, and managing code entries in the registry
- **Git Manager**: For managing Git repositories and operations
- **System Manager**: For system monitoring and resource management
- **Test Runner**: For running and managing tests

The Keeper application is designed to help users navigate efficiently to the right capabilities within the Wippy platform,
maintaining conversational context throughout interactions with different specialized agents.
It acts as the central coordination point for the entire system.


[wippy-documentation]: https://docs.wippy.ai
[releases-page]: https://github.com/wippyai/app-keeper/releases
