{{/*
=============================================================================
OPSC CHART - HELPER TEMPLATES
=============================================================================
*/}}

{{/*
Image Pull Secret - Creates docker config JSON from registry credentials
*/}}
{{- define "imagePullSecret" }}
  {{- if .Values.registryCredentials -}}
    {{- $credType := typeOf .Values.registryCredentials -}}
    {{- if eq $credType "[]interface {}" -}}
      {{- include "multipleCreds" . | b64enc }}
    {{- else if eq $credType "map[string]interface {}" }}
      {{- if and .Values.registryCredentials.username .Values.registryCredentials.password }}
        {{- with .Values.registryCredentials }}
          {{- printf "{\"auths\":{\"%s\":{\"username\":\"%s\",\"password\":\"%s\",\"email\":\"%s\",\"auth\":\"%s\"}}}" .registry .username .password .email (printf "%s:%s" .username .password | b64enc) | b64enc }}
        {{- end }}
      {{- end }}
    {{- end -}}
  {{- end }}
{{- end }}

{{/*
Multiple Credentials - Handles list of registry credentials
*/}}
{{- define "multipleCreds" -}}
{
  "auths": {
    {{- range $i, $m := .Values.registryCredentials }}
    {{- if and $m.registry $m.username $m.password }}
    {{- if $i }},{{ end }}
    "{{ $m.registry }}": {
      "username": "{{ $m.username }}",
      "password": "{{ $m.password }}",
      "email": "{{ $m.email | default "" }}",
      "auth": "{{ printf "%s:%s" $m.username $m.password | b64enc }}"
    }
    {{- end }}
    {{- end }}
  }
}
{{- end }}

{{/*
Valid Git Reference - Builds appropriate spec.ref given git branch, commit, tag, or semver
*/}}
{{- define "validRef" -}}
{{- if .commit -}}
{{- if not .branch -}}
{{- fail "A valid branch is required when a commit is specified!" -}}
{{- end -}}
branch: {{ .branch | quote }}
commit: {{ .commit }}
{{- else if .semver -}}
semver: {{ .semver | quote }}
{{- else if .tag -}}
tag: {{ .tag }}
{{- else -}}
branch: {{ .branch | quote }}
{{- end -}}
{{- end -}}

{{/*
Git Ignore - Common file extensions to exclude from git sources
*/}}
{{- define "gitIgnore" -}}
  ignore: |
    # exclude file extensions
    /**/*.md
    /**/*.txt
    /**/*.sh
    !/chart/tests/scripts/*.sh
{{- end -}}

{{/*
Common Labels - Labels applied to all resources
*/}}
{{- define "commonLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ default .Chart.Version .Chart.AppVersion | replace "+" "_" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: "opsc"
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/*
Git Credentials Global - Build git credentials secret reference for global repos
*/}}
{{- define "gitCredsGlobal" -}}
{{- if .Values.git.existingSecret -}}
secretRef:
  name: {{ .Values.git.existingSecret }}
{{- else if coalesce .Values.git.credentials.username .Values.git.credentials.password .Values.git.credentials.caFile .Values.git.credentials.privateKey .Values.git.credentials.publicKey .Values.git.credentials.knownHosts "" -}}
secretRef:
  name: {{ $.Release.Name }}-git-credentials
{{- end -}}
{{- end -}}

{{/*
Git Credentials Extended - Build git credentials for individual packages
*/}}
{{- define "gitCredsExtended" -}}
{{- if .packageGitScope.existingSecret -}}
secretRef:
  name: {{ .packageGitScope.existingSecret }}
{{- else if and (.packageGitScope.credentials) (coalesce .packageGitScope.credentials.username .packageGitScope.credentials.password .packageGitScope.credentials.caFile .packageGitScope.credentials.privateKey .packageGitScope.credentials.publicKey .packageGitScope.credentials.knownHosts "") -}}
secretRef:
  name: {{ .releaseName }}-{{ .name }}-git-credentials
{{- else -}}
{{- include "gitCredsGlobal" .rootScope }}
{{- end -}}
{{- end -}}

{{/*
Git Credentials - Pointer to appropriate git credentials template
*/}}
{{- define "gitCreds" -}}
{{- include "gitCredsGlobal" . }}
{{- end -}}

{{/*
Get Repository Type - Returns the type of a Helm repository
*/}}
{{- define "getRepoType" -}}
  {{- $repoName := .repoName -}}
  {{- range .allRepos -}}
    {{- if eq .name $repoName -}}
      {{- print .type -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Resource Name - Converts string to legal Kubernetes resource name
*/}}
{{- define "resourceName" -}}
  {{- regexReplaceAll "\\W+" . "-" | trimPrefix "-" | trunc 63 | trimSuffix "-" | kebabcase -}}
{{- end -}}

{{/*
Values Secret - Creates a secret containing package values (common, defaults, overlays)
For OpsContinuum, we use a simpler approach than Big Bang since we're using upstream charts directly.
*/}}
{{- define "values-secret" -}}
{{- $defaults := default (dict) (fromYaml .defaults) }}
{{- $packageValues := default dict .package.values -}}
apiVersion: v1
kind: Secret
metadata:
  name: {{ .root.Release.Name }}-{{ .name }}-values
  namespace: {{ .root.Release.Namespace }}
type: generic
stringData:
  common: |
    {}
  defaults: |
    {{- toYaml $defaults | nindent 4 }}
  overlays: |
    {{- toYaml $packageValues | nindent 4 }}
{{- end -}}

{{/*
Git Credentials Secret - Creates secret for package-specific git credentials
*/}}
{{- define "gitCredsSecret" -}}
{{- $name := .name }}
{{- $releaseName := .releaseName }}
{{- $releaseNamespace := .releaseNamespace }}
{{- with .targetScope -}}
{{- if and (eq .sourceType "git") .enabled }}
{{- if .git }}
{{- with .git -}}
{{- if not .existingSecret }}
{{- if .credentials }}
{{- if coalesce .credentials.username .credentials.password .credentials.caFile .credentials.privateKey .credentials.publicKey .credentials.knownHosts -}}
{{- $http := coalesce .credentials.username .credentials.password .credentials.caFile "" }}
{{- $ssh := coalesce .credentials.privateKey .credentials.publicKey .credentials.knownHosts "" }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ $releaseName }}-{{ $name }}-git-credentials
  namespace: {{ $releaseNamespace }}
type: Opaque
data:
  {{- if $http }}
  {{- if .credentials.caFile }}
  caFile: {{ .credentials.caFile | b64enc }}
  {{- end }}
  {{- if and .credentials.username (not .credentials.password) }}
  {{- printf "%s - When using http git username, password must be specified" $name | fail }}
  {{- end }}
  {{- if and .credentials.password (not .credentials.username) }}
  {{- printf "%s - When using http git password, username must be specified" $name | fail }}
  {{- end }}
  {{- if and .credentials.username .credentials.password }}
  username: {{ .credentials.username | b64enc }}
  password: {{ .credentials.password | b64enc }}
  {{- end }}
  {{- else }}
  {{- if not (and (and .credentials.privateKey .credentials.publicKey) .credentials.knownHosts) }}
  {{- printf "%s - When using ssh git credentials, privateKey, publicKey, and knownHosts must all be specified" $name | fail }}
  {{- end }}
  identity: {{ .credentials.privateKey | b64enc }}
  identity.pub: {{ .credentials.publicKey | b64enc }}
  known_hosts: {{ .credentials.knownHosts | b64enc }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Add Value If Set - Conditionally adds a value to YAML output
Args: [0] = key name, [1] = value to check
*/}}
{{- define "opsc.addValueIfSet" -}}
  {{- $key := (index . 0) }}
  {{- $value := (index . 1) }}
  {{- if not (kindIs "invalid" $value) }}
    {{- if kindIs "string" $value }}
      {{- printf "\n%s" $key }}: {{ $value | quote }}
    {{- else if kindIs "slice" $value }}
      {{- printf "\n%s" $key }}:
        {{- range $value }}
          {{- if kindIs "string" . }}
            {{- printf "\n  - %s" (. | quote) }}
          {{- else }}
            {{- printf "\n  - %v" . }}
          {{- end }}
        {{- end }}
    {{- else }}
      {{- printf "\n%s" $key }}: {{ $value }}
    {{- end }}
  {{- end }}
{{- end -}}
