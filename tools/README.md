# Tools Directory

This directory contains utility scripts and one-time use tools for the Phone Photo Management Scripts project.

## Scripts

### `transfer_project.sh`
**Purpose**: Generate comprehensive project transfer documentation  
**Usage**: One-time script to create project transfer documents when moving between environments  
**When to use**: 
- When transferring the project to a new environment
- When creating portfolio documentation
- When documenting the current state of the project

**Example**:
```bash
cd tools/
bash transfer_project.sh
```

## Guidelines

- **One-time scripts** go in this directory
- **Core functionality** stays in the root directory
- **Documentation generators** belong here
- **Maintenance scripts** belong here
- **Development helper scripts** belong here

## Adding New Tools

When adding new tools:
1. Place them in this directory
2. Update this README with description and usage
3. Ensure they don't contain sensitive data
4. Test them before committing

## Note

These tools are not part of the core photo management functionality. They are utilities for development, maintenance, and documentation purposes.
