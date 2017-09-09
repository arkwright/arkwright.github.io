image=$1

echo $image

rm $image.bmp
convert $image.png -colorspace Gray -scale "100%" -auto-gamma -auto-level -brightness-contrast 10x10 $image.bmp

rm $image.svg
potrace -s -H 400pt -t 10 -z black -C "#444444" --tight $image.bmp
