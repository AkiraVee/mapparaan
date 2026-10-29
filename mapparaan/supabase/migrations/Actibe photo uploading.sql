-- Allow logged-in users to upload memory photos
CREATE POLICY "Users can upload memory photos" 
ON storage.objects FOR INSERT 
TO authenticated 
WITH CHECK (bucket_id = 'memory-photos');

-- Allow anyone to view memory photos
CREATE POLICY "Anyone can view memory photos" 
ON storage.objects FOR SELECT 
TO public 
USING (bucket_id = 'memory-photos');