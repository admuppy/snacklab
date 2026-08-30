# SnackLab — CKA 모의고사 "콘텐츠" 이미지
# (snacklab-cka-course)
#
# k8s 코스와 동일한 계약: 코스 번들(course.json + modules/)을 /course 에 담기만 한다.
# 차트의 course initContainer 가 /courses/cka 로 복사하고, 포털이 CONTENT_DIRS 로 로드한다.
# 학습자 파드 환경 이미지는 k8s 트랙과 공유한다 (course.json 의 image = snacklab-k8s).
#
# 빌드 컨텍스트 = 리포지토리 루트 (build.sh cka-course [tag]).
FROM busybox:1.36
COPY courses/cka/course.json /course/course.json
COPY courses/cka/modules     /course/modules
RUN ls -1 /course/modules | wc -l > /course/.module-count
