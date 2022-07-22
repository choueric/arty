# Intro

An Dart program to access Jfrog Artifactory using its RESTful API:
https://www.jfrog.com/confluence/display/JFROG/Artifactory+REST+API#ArtifactoryRESTAPI-RetrieveArtifact

# Configuration

The configuration file is `$HOME/.arty.json`. Example:

```json
{
  "current": "kernel",
  "baseUri": "https://artifact.xxx.com/artifactory",
  "token": "kajfjafjfjfjfjadjf",
  "repoList": [
    {
      "name": "kernel",
      "key": "linux-kernel",
      "folderPath": "fw/new"
    }
  ]
}
```

# Commands

- list: list the repositories in configuration file.
- choose: change the current repo

- ls: list the folders or files on Artifactory.
- get: download one artifact on Artifactory with specified download URL.
