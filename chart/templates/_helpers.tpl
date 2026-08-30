{{- define "snacklab.fullname" -}}
{{- if contains "snacklab" .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-snacklab" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "snacklab.labels" -}}
app.kubernetes.io/name: snacklab
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "snacklab.selectorLabels" -}}
app.kubernetes.io/name: snacklab
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "snacklab.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "snacklab.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}
