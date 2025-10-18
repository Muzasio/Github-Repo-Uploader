
# GitHub Repository Uploader


A powerful, **GUI-driven Bash script** for managing GitHub repositories with an intuitive graphical interface. Streamline your GitHub workflow with features for creating, updating, cloning repositories, and managing your account - all through a simple point-and-click interface.


![Language](https://img.shields.io/badge/Language-Bash-green.svg)
![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)
## Features

### 🔄 Repository Management
- **Create New Repositories**: Upload local projects to GitHub with custom names, descriptions, licenses, and visibility.  
- **Update Existing Repositories**: Push changes with automatic commit messages.  
- **Clone Repositories**: Clone any repo with progress tracking.
- **Added manual license function
### 🔍 Repository Insights 
- **View Repo Information**: Stars, forks, issues, creation date, and more.(not tested yet)  
- **Check Issues**: Open/closed issue counts at a glance.  
- **Folder Content Preview**: File counts, sizes, and structure before upload.

### 🔐 Account Management
- **Secure Credential Storage**: Tokens stored with proper file permissions.  
- **Token Validation**: Automatic validation of GitHub credentials.  
- **Easy Management**: Add, update, or remove tokens seamlessly.



## Prerequisites


- git - Version control system
- curl - HTTP client for API calls
- jq - JSON processor for API responses
- zenity - GUI dialog boxes for user interaction

Ensure the following packages are installed:

```bash
  sudo apt update
sudo apt install git curl jq zenity
```

GitHub Token

Create a Personal Access Token
 with repo scope.


 💻 Usage

Run from any directory():

```bash
./github_uploader.sh
```
or

 Set it in nautilus script folder to make it appear in context menu(recommended)

**Workflow**

* Right click on the folder u want to upload its content as repo.
* Make sure it has all the content. 
* Enter your credentials when prompted (saved securely).
* Preview folder contents.
* hoose an action from the menu:
* Create New Repository
* Update Existing Repository
* Clone Repository
* View Repository Info
* Check Issues
* Manage Account Settings


### 🔧 Advanced Features

#### Logging

* Logs saved in /tmp/github_uploader_YYYYMMDD_HHMMSS.log.
* Includes API requests, Git outputs, and errors.

#### Error Handling

* Handles common issues:
* Network failures
* Invalid credentials
* API rate limits
* Repository conflicts
* File permission issues

#### GitHub API

* Uses REST API v3.
* Handles authentication, JSON parsing, and error codes.

**Tested on Pop Os only (using Nautilus)**


## ⚠️ Important Security Considerations

This script is designed with intentional security simplifications for individual use:

- Plain Text Storage: Credentials are stored in plain text configuration files
- Token Visibility: GitHub tokens may be visible in process lists during execution
- Local Logging: API responses and operations are logged to local files
- No Encryption: No encryption is applied to stored credentials

### 🎯 Intended Audience
This tool is specifically designed for:

- Individual developers
- Personal projects
- Learning and educational purposes
- Quick prototyping and scripting

### Not suitable for:

- Enterprise environments
- Team projects with shared credentials
- Production systems requiring high security
- Environments with strict compliance requirements



### ⚠️ Disclaimer
This tool is provided as-is for individual developers. Users are responsible for:

Implementing additional security measures as needed(Encryption or hashing)

Safeguarding their GitHub credentials

Understanding the security implications of plain text storage

Using appropriate security practices for their environment 

