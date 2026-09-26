# SnackLab — Kubernetes 심화 과정 "콘텐츠" 이미지
# (snacklab-k8s-course)
#
# 이 이미지는 코스 번들(course.json + modules/)을 /course 에 담기만 한다. 차트의 course
# initContainer 가 `cp -r /course/* /dst/k8s/` 로 포털 공유볼륨(/courses/k8s)에 복사하고,
# 포털은 CONTENT_DIRS=/app/v0.1/content:/courses 로 이를 하나의 코스로 로드한다.
# (학습자 파드 환경 이미지는 별개다 → k8s-lab, course.json 의 image 필드가 가리킨다.)
#
# 빌드 컨텍스트 = 리포지토리 루트 (build.sh k8s-course [tag]).
FROM busybox:1.36
COPY courses/k8s/course.json /course/course.json
COPY courses/k8s/modules     /course/modules
# 무결성 확인용(빌드 시): 모듈 수 출력
RUN ls -1 /course/modules | wc -l > /course/.module-count
