create policy "Delegated administrators read reviews" on public.reviews for select to authenticated
using (public.has_admin_permission('reviews.view'));
